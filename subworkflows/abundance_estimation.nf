include { INDEX_DEREP_MAGS } from '../modules/abundance_estimation'
include { MAP_READS_TO_DEREP_MAGS } from '../modules/abundance_estimation'
include { GET_GENOME_LENGTHS } from '../modules/abundance_estimation'
include { ESTIMATE_MAG_ABUNDANCE } from '../modules/abundance_estimation'
include { COLLATE_PARTITIONS } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_MAG_ABUNDANCE } from '../modules/data_prep'

workflow ESTIMATE_ABUNDANCE {
    take:
        mags_derep
        reads
        q2_cache
    main:
        mags_derep_index = INDEX_DEREP_MAGS(mags_derep, q2_cache)
        combined = reads.combine(mags_derep_index)
        reads_to_mags = MAP_READS_TO_DEREP_MAGS(combined, q2_cache) | collect(flat: false)
        maps_all = COLLATE_PARTITIONS(reads_to_mags, "${params.runId}_reads_to_derep_mags", "assembly collate-alignments", "--i-alignments", "--o-collated-alignments", true)
        lengths = GET_GENOME_LENGTHS(mags_derep, q2_cache)
        abundance = ESTIMATE_MAG_ABUNDANCE(maps_all, lengths, q2_cache)
        if (params.mag_abundance.fetchArtifact) {
            FETCH_ARTIFACT_MAG_ABUNDANCE(abundance)
        }
    emit:
        feature_table = abundance
}
