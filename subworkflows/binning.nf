include { INDEX_CONTIGS } from '../modules/genome_assembly'
include { MAP_READS_TO_CONTIGS } from '../modules/genome_assembly'
include { BIN_CONTIGS_METABAT } from '../modules/contig_binning'
include { EVALUATE_BINS_BUSCO } from '../modules/contig_binning'
include { VISUALIZE_BUSCO } from '../modules/contig_binning'
include { FETCH_BUSCO_DB } from '../modules/contig_binning'
include { FILTER_MAGS } from '../modules/contig_binning'
include { PARTITION_ARTIFACT } from '../modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_BINS } from '../modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_BUSCO_RESULTS } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_MAGS } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_MAGS_FILTERED } from '../modules/data_prep'

workflow BIN {
    take:
        contigs
        reads
        q2_cache
    main:
        indexed_contigs = INDEX_CONTIGS(contigs, q2_cache)
        indexed_contigs_with_reads = indexed_contigs.combine(reads, by: 0)

        mapped_reads = MAP_READS_TO_CONTIGS(indexed_contigs_with_reads, q2_cache)
        contigs_with_maps = contigs.combine(mapped_reads, by: 0)

        bins = BIN_CONTIGS_METABAT(contigs_with_maps, q2_cache)
        bins_all = BIN_CONTIGS_METABAT.out.bins | map { _id, _key -> _key } | collect
        bins_all = COLLATE_BINS(bins_all, "${params.runId}_mags", "types collate-sample-data-mags", "--i-mags", "--o-collated-mags", true)

        if (params.binning.fetchArtifact) {
            FETCH_ARTIFACT_MAGS(bins_all)
        }    

        busco_db = FETCH_BUSCO_DB(q2_cache)
        lineages = Channel.from(params.binning.qc.busco.lineageDatasets.split(","))
        bins_with_lineage = lineages.combine(BIN_CONTIGS_METABAT.out.bins)
        busco_results_partitioned = EVALUATE_BINS_BUSCO(bins_with_lineage, busco_db, q2_cache)
        busco_results = COLLATE_BUSCO_RESULTS(busco_results_partitioned | map { _id, _key -> _key } | collect, "${params.runId}_busco_results", "moshpit collate-busco-results", "--i-busco-results", "--o-collated-busco-results", true)
        VISUALIZE_BUSCO(busco_results, q2_cache)

        if (params.binning.qc.filtering.enabled) {
            bins = FILTER_MAGS(bins_all, busco_results, "mag", q2_cache)
            if (params.binning.qc.filtering.fetchArtifact) {
                FETCH_ARTIFACT_MAGS_FILTERED(bins)   
            }
            bins = PARTITION_ARTIFACT(bins, "${params.runId}_mags_filtered_partitioned_", "types partition-sample-data-mags", "--i-mags", "--o-partitioned-mags") | flatten
            bins = bins.map { partition ->
                def path = java.nio.file.Paths.get(partition.toString())
                def filename = path.getFileName().toString()
                tuple(filename.substring("${params.runId}_mags_filtered_partitioned_".length()), partition)
            }
        } else {
            bins = BIN_CONTIGS_METABAT.out.bins
        }

    emit:
        bins = bins
        contig_map = BIN_CONTIGS_METABAT.out.contig_map
        unbinned_contigs = BIN_CONTIGS_METABAT.out.unbinned_contigs
        busco_results = busco_results
}

workflow BIN_NO_BUSCO {
    take:
        contigs
        reads
        q2_cache
    main:
        indexed_contigs = INDEX_CONTIGS(contigs, q2_cache)
        indexed_contigs_with_reads = indexed_contigs.combine(reads, by: 0)

        mapped_reads = MAP_READS_TO_CONTIGS(indexed_contigs_with_reads, q2_cache)
        contigs_with_maps = contigs.combine(mapped_reads, by: 0)

        bins = BIN_CONTIGS_METABAT(contigs_with_maps, q2_cache)

        if (params.binning.fetchArtifact) {
            bins_all = COLLATE_BINS(bins | map { _id, _key -> _key } | collect, "${params.runId}_mags", "types collate-sample-data-mags", "--i-mags", "--o-collated-mags", true)
            FETCH_ARTIFACT_MAGS(bins_all)
        }
    emit:
        bins = BIN_CONTIGS_METABAT.out.bins
        contig_map = BIN_CONTIGS_METABAT.out.contig_map
        unbinned_contigs = BIN_CONTIGS_METABAT.out.unbinned_contigs
}
