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
        if (params.binning.qc.busco.enabled && params.binning.qc.filtering.enabled) {
            mags_all = COLLATE_PARTITIONS(bins, "${params.runId}_mags_filtered", "types collate-sample-data-mags", "--i-mags", "--o-collated-mags", true)
        } else {
            mags_all = COLLATE_PARTITIONS(bins, "${params.runId}_mags", "types collate-sample-data-mags", "--i-mags", "--o-collated-mags", true)
        }
        minhashes = CALCULATE_MINHASHES(mags_all, q2_cache)
        distance_matrix = COMPARE_MINHASHES(minhashes, q2_cache)
        DEREPLICATE_MAGS(mags_all, distance_matrix, q2_cache)

        if (params.dereplication.fetchArtifact) {
            FETCH_ARTIFACT_MAGS_DEREP(DEREPLICATE_MAGS.out.bins_derep)
        }
    emit:
        bins_derep = DEREPLICATE_MAGS.out.bins_derep
        feature_table = DEREPLICATE_MAGS.out.feature_table
        bins_filtered = bins
}
