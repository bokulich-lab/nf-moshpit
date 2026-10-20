include { EVALUATE_BINS_BUSCO } from '../modules/contig_binning'
include { EVALUATE_BINS_CHECKM } from '../modules/contig_binning'
include { VISUALIZE_BUSCO } from '../modules/contig_binning'
include { FILTER_MAGS } from '../modules/contig_binning'
include { COLLATE_PARTITIONS as COLLATE_BINS } from '../modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_FILTERED_BINS } from '../modules/data_prep'
include { COLLATE_BUSCO_RESULTS } from '../modules/contig_binning'
include { COLLATE_PARTITIONS as COLLATE_UNBINNED_CONTIGS } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_MAGS } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_MAGS_FILTERED } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_BUSCO_RESULTS } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_UNBINNED_CONTIGS } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_CONTIG_MAP } from '../modules/data_prep'

include { COLLATE_PARTITIONS as COLLATE_CONTIG_MAPS } from '../modules/data_prep'

workflow BINNING_QC {
    take:
        binner
        bins
        contig_map
        unbinned_contigs
        q2_cache
        with_busco
        busco_db
    main:
        qzv_outputs = Channel.empty()
        busco_results_out = Channel.empty()
        contig_map_all = COLLATE_CONTIG_MAPS(
            contig_map.collect(flat: false),
            "${params.runId}_contig_map_${binner}",
            "types collate-contig-maps", "--i-contig-maps", "--o-collated-contig-maps", true
        ).result
        bins_all = bins | collect(flat: false)
        bins_all = COLLATE_BINS(
            bins_all,
            "${params.runId}_mags_${binner}",
            "types collate-sample-data-mags",
            "--i-mags",
            "--o-collated-mags",
            true
        ).result

        unbinned_all = unbinned_contigs | collect(flat: false)
        unbinned_all = COLLATE_UNBINNED_CONTIGS(
            unbinned_all,
            "${params.runId}_unbinned_contigs_${binner}",
            "types collate-contigs",
            "--i-contigs",
            "--o-collated-contigs",
            true
        ).result

        if (binner != 'das_tool' && params.binning.fetchArtifact) {
            FETCH_ARTIFACT_UNBINNED_CONTIGS(unbinned_all)
            FETCH_ARTIFACT_CONTIG_MAP(contig_map_all)
            FETCH_ARTIFACT_MAGS(bins_all)
        }

        if (params.binning.qc.checkm.enabled) {
            EVALUATE_BINS_CHECKM(Channel.value(binner), bins_all)
            qzv_outputs = qzv_outputs.mix(EVALUATE_BINS_CHECKM.out.qzv)
        }

        if (with_busco) {
            lineages = Channel.of(params.binning.qc.busco.lineageDatasets.split(","))

            bins_for_busco = bins.combine(unbinned_contigs, by: 0)

            bins_with_lineage = lineages.combine(bins_for_busco)
            busco_results_partitioned = EVALUATE_BINS_BUSCO(
                Channel.value(binner),
                bins_with_lineage,
                busco_db
            ).busco_results
            busco_results_by_lineage = busco_results_partitioned.groupTuple(by: 0)

            busco_results = COLLATE_BUSCO_RESULTS(
                busco_results_by_lineage.map { it[0] },
                busco_results_by_lineage.map { it[1..-1] },
                "${params.runId}_busco_results_${binner}",
                "mag collate-busco-results",
                "--i-results",
                "--o-collated-results",
                true
            )
            VISUALIZE_BUSCO(Channel.value(binner), busco_results.collated_results, q2_cache)
            qzv_outputs = qzv_outputs.mix(VISUALIZE_BUSCO.out.qzv)
            busco_results_out = busco_results.collated_results

            if (binner != 'das_tool' && params.binning.qc.busco.fetchArtifact) {
                FETCH_ARTIFACT_BUSCO_RESULTS(busco_results.collated_results.map { it[1] })
            }

            if (params.binning.qc.filtering.enabled) {
                filtered_busco_results = busco_results.collated_results
                    .filter { lineage, _results ->
                        params.binning.qc.busco.selectLineage.split(",").any { selectedLineage ->
                            lineage.toString().contains(selectedLineage.trim())
                        }
                    }

                combined = bins.combine(filtered_busco_results)

                bins = FILTER_MAGS(
                    Channel.value(binner),
                    combined.map { _id, _bins, lineage, _busco_results -> [_id, _bins, lineage] },
                    combined.map { _id, _bins, _lineage, busco_results -> busco_results },
                    "mag",
                    q2_cache
                ).mags_filtered
                bins = bins.map { _id, _bins, _lineage -> [_id, _bins] }
                bins_all = bins | collect(flat: false)
                bins_all = COLLATE_FILTERED_BINS(
                    bins_all,
                    "${params.runId}_mags_${binner}_filtered_${params.binning.qc.busco.selectLineage}",
                    "types collate-sample-data-mags",
                    "--i-mags",
                    "--o-collated-mags",
                    true
                ).result
                if (binner != 'das_tool' && params.binning.qc.filtering.fetchArtifact) {
                    FETCH_ARTIFACT_MAGS_FILTERED(bins_all)
                }
            }
        }

    emit:
        bins = bins
        contig_map = contig_map
        contig_map_collated = contig_map_all
        unbinned_contigs = unbinned_contigs
        busco_results = busco_results_out
        bins_collated = bins_all
        completion = bins_all.mix(contig_map_all).mix(unbinned_all).mix(busco_results_out)
        qzv = qzv_outputs
}
