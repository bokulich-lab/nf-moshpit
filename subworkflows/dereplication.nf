include { CALCULATE_MINHASHES } from '../modules/dereplication'
include { COMPARE_MINHASHES } from '../modules/dereplication'
include { DEREPLICATE_MAGS } from '../modules/dereplication'
include { FILTER_MAGS } from '../modules/dereplication'

workflow DEREPLICATE {
    take:
        bins
        busco_results
        q2_cache
    main:
        if (params.dereplication.filtering.enabled) {
            bins = FILTER_MAGS(bins, busco_results, "mag", q2_cache)
        }
        minhashes = CALCULATE_MINHASHES(bins, q2_cache)
        distance_matrix = COMPARE_MINHASHES(minhashes, q2_cache)
        DEREPLICATE_MAGS(bins, distance_matrix, q2_cache)
    emit:
        bins_derep = DEREPLICATE_MAGS.out.bins_derep
        feature_table = DEREPLICATE_MAGS.out.feature_table
        bins_filtered = bins
}
