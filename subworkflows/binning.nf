include { BIN_CONTIGS_METABAT } from '../modules/contig_binning'
include { EVALUATE_BINS_BUSCO } from '../modules/contig_binning'
include { EVALUATE_BINS_CHECKM } from '../modules/contig_binning'
include { VISUALIZE_BUSCO } from '../modules/contig_binning'
include { FETCH_BUSCO_DB } from '../modules/contig_binning'
include { FILTER_MAGS } from '../modules/contig_binning'
include { COLLATE_PARTITIONS as COLLATE_BINS } from '../modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_FILTERED_BINS } from '../modules/data_prep'
include { COLLATE_BUSCO_RESULTS } from '../modules/contig_binning'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_MAGS } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_MAGS_FILTERED } from '../modules/data_prep'

workflow BIN {
    take:
        contigs
        maps
        q2_cache
    main:
        contigs_with_maps = contigs.combine(maps, by: 0)

        bins = BIN_CONTIGS_METABAT(contigs_with_maps)
        bins_all = BIN_CONTIGS_METABAT.out.bins | collect(flat: false)
        bins_all = COLLATE_BINS(bins_all, "${params.runId}_mags", "types collate-sample-data-mags", "--i-mags", "--o-collated-mags", true)

        if (params.binning.fetchArtifact) {
            FETCH_ARTIFACT_MAGS(bins_all)
        }

        if (params.binning.qc.checkm.enabled) {
            EVALUATE_BINS_CHECKM(bins_all)
        }

        busco_db = FETCH_BUSCO_DB()
        lineages = Channel.of(params.binning.qc.busco.lineageDatasets.split(","))
        bins_with_lineage = BIN_CONTIGS_METABAT.out.bins.combine(BIN_CONTIGS_METABAT.out.unbinned_contigs, by: 0)
        bins_with_lineage_unbinned = lineages.combine(bins_with_lineage)

        bins_with_lineage_unbinned.view()

        busco_results_partitioned = EVALUATE_BINS_BUSCO(bins_with_lineage_unbinned, busco_db)
        busco_results_by_lineage = busco_results_partitioned.groupTuple(by: 0)
        
        busco_results = COLLATE_BUSCO_RESULTS(
            busco_results_by_lineage.map { it[0] },          // lineage
            busco_results_by_lineage.map { it[1..-1] },      // ids_and_paths
            "${params.runId}_busco_results", 
            "annotate collate-busco-results", 
            "--i-results", 
            "--o-collated-results", 
            true
        )
        VISUALIZE_BUSCO(busco_results, q2_cache)

        if (params.binning.qc.filtering.enabled) {
            filtered_busco_results = busco_results
                .filter { lineage -> 
                    def lineage_element = lineage[0]
                    def matches = params.binning.qc.busco.selectLineage.split(",").any { selectedLineage ->
                        def trimmed = selectedLineage.trim()
                        def contains = lineage_element.contains(trimmed)
                        contains
                    }
                    matches
                }

            combined = BIN_CONTIGS_METABAT.out.bins.combine(filtered_busco_results)

            bins = FILTER_MAGS(combined.map { _id, _bins, lineage, busco_results -> [_id, _bins, lineage] }, combined.map { _id, _bins, lineage, busco_results -> busco_results }, "mag", q2_cache)
            bins_all = bins | collect(flat: false)
            bins_all = COLLATE_FILTERED_BINS(bins_all, "${params.runId}_mags_filtered_${params.binning.qc.busco.selectLineage}", "types collate-sample-data-mags", "--i-mags", "--o-collated-mags", true)
            if (params.binning.qc.filtering.fetchArtifact) {
                FETCH_ARTIFACT_MAGS_FILTERED(bins_all)   
            }
        } else {
            bins = BIN_CONTIGS_METABAT.out.bins
        }

    emit:
        bins = bins
        contig_map = BIN_CONTIGS_METABAT.out.contig_map
        unbinned_contigs = BIN_CONTIGS_METABAT.out.unbinned_contigs
        busco_results = busco_results.collated_results
        bins_collated = bins_all
}

workflow BIN_NO_BUSCO {
    take:
        contigs
        maps
        q2_cache
    main:
        contigs_with_maps = contigs.combine(maps, by: 0)

        bins = BIN_CONTIGS_METABAT(contigs_with_maps)
        bins_all = bins.bins | collect(flat: false)
        bins_all = COLLATE_BINS(bins_all, "${params.runId}_mags", "types collate-sample-data-mags", "--i-mags", "--o-collated-mags", true)
        if (params.binning.fetchArtifact) {
            FETCH_ARTIFACT_MAGS(bins_all)
        }
        if (params.binning.qc.checkm.enabled) {
            EVALUATE_BINS_CHECKM(bins_all)
        }
    emit:
        bins = BIN_CONTIGS_METABAT.out.bins
        contig_map = BIN_CONTIGS_METABAT.out.contig_map
        unbinned_contigs = BIN_CONTIGS_METABAT.out.unbinned_contigs
        bins_collated = bins_all
}
