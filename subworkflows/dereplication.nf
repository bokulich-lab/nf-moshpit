include { CALCULATE_MINHASHES } from '../modules/dereplication'
include { COMPARE_MINHASHES } from '../modules/dereplication'
include { DEREPLICATE_MAGS } from '../modules/dereplication'
include { COLLATE_PARTITIONS } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_MAGS_DEREP } from '../modules/data_prep'

workflow DEREPLICATE {
    take:
        bins
        q2_cache
    main:
        minhashes = CALCULATE_MINHASHES(bins, q2_cache)
        distance_matrix = COMPARE_MINHASHES(minhashes, q2_cache)
        DEREPLICATE_MAGS(bins, distance_matrix, q2_cache)

        if (params.dereplication.fetchArtifact) {
            FETCH_ARTIFACT_MAGS_DEREP(DEREPLICATE_MAGS.out.bins_derep)
        }
    emit:
        bins_derep = DEREPLICATE_MAGS.out.bins_derep
        feature_table = DEREPLICATE_MAGS.out.feature_table
}
