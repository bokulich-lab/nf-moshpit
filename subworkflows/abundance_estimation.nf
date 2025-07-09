include { INDEX_DEREP_MAGS } from '../modules/abundance_estimation'
include { MAP_READS_TO_DEREP_MAGS } from '../modules/abundance_estimation'
include { GET_GENOME_LENGTHS as GET_MAG_LENGTHS } from '../modules/abundance_estimation'
include { GET_GENOME_LENGTHS as GET_CONTIG_LENGTHS } from '../modules/abundance_estimation'
include { ESTIMATE_ABUNDANCE as ESTIMATE_MAG_ABUNDANCE } from '../modules/abundance_estimation'
include { ESTIMATE_ABUNDANCE as ESTIMATE_CONTIG_ABUNDANCE } from '../modules/abundance_estimation'
include { COLLATE_PARTITIONS } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_MAG_ABUNDANCE } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_CONTIG_ABUNDANCE } from '../modules/data_prep'

workflow MAG_ABUNDANCE {
    take:
        mags_derep
        reads
        q2_cache
    main:
        mags_derep_index = INDEX_DEREP_MAGS(mags_derep, q2_cache)
        combined = reads.combine(mags_derep_index)
        reads_to_mags = MAP_READS_TO_DEREP_MAGS(combined, q2_cache) | collect(flat: false)
        maps_all = COLLATE_PARTITIONS(reads_to_mags, "${params.runId}_reads_to_derep_mags", "assembly collate-alignments", "--i-alignment-maps", "--o-collated-alignment-maps", true)
        lengths = GET_MAG_LENGTHS(mags_derep, q2_cache, "mags_derep")
        abundance = ESTIMATE_MAG_ABUNDANCE(maps_all, lengths, "mags_derep",q2_cache)
        if (params.abundance_estimation.fetchArtifact) {
            FETCH_ARTIFACT_MAG_ABUNDANCE(abundance)
        }
    emit:
        feature_table = abundance
}

workflow CONTIG_ABUNDANCE {
    take:
        contigs
        maps
        q2_cache
    main:
        lengths = GET_CONTIG_LENGTHS(contigs, q2_cache, "contigs")
        abundance = ESTIMATE_CONTIG_ABUNDANCE(maps, lengths, "contigs", q2_cache)
        if (params.abundance_estimation.fetchArtifact) {
            FETCH_ARTIFACT_CONTIG_ABUNDANCE(abundance)
        }
    emit:
        feature_table = abundance
}
