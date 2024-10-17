include { INDEX_DEREP_MAGS } from '../modules/abundance_estimation'
include { MAP_READS_TO_DEREP_MAGS } from '../modules/abundance_estimation'
include { GET_GENOME_LENGTHS } from '../modules/abundance_estimation'
include { ESTIMATE_MAG_ABUNDANCE } from '../modules/abundance_estimation'

workflow ESTIMATE_ABUNDANCE {
    take:
        mags_derep
        reads
        q2_cache
    main:
        mags_derep_index = INDEX_DEREP_MAGS(mags_derep, q2_cache)
        reads_to_mags = MAP_READS_TO_DEREP_MAGS(mags_derep_index, reads, q2_cache)
        lengths = GET_GENOME_LENGTHS(mags_derep, q2_cache)
        abundance = ESTIMATE_MAG_ABUNDANCE(reads_to_mags, lengths, q2_cache)
    emit:
        feature_table = abundance
}
