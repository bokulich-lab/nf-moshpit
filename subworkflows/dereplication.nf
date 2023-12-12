include { CALCULATE_MINHASHES } from '../modules/dereplication'
include { COMPARE_MINHASHES } from '../modules/dereplication'
include { DEREPLICATE_MAGS } from '../modules/dereplication'

workflow DEREPLICATE {
    take:
        bins
        q2Cache
    main:
        minhashes = CALCULATE_MINHASHES(bins, q2Cache)
        distance_matrix = COMPARE_MINHASHES(minhashes)
        DEREPLICATE_MAGS(bins, distance_matrix)
    emit:
        bins_derep = DEREPLICATE_MAGS.out.bins_derep
        feature_table = DEREPLICATE_MAGS.out.feature_table
}
