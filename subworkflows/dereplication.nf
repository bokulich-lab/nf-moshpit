include { CALCULATE_MINHASHES } from '../modules/dereplication'
include { COMPARE_MINHASHES } from '../modules/dereplication'
include { DEREPLICATE_MAGS } from '../modules/dereplication'
include { COLLATE_PARTITIONS } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_MAGS_DEREP } from '../modules/data_prep'
include { CHECKPOINT_DEREP_MAGS } from '../modules/provenance'

workflow DEREPLICATE {
    take:
        bins
        q2_cache
    main:
        minhashes = CALCULATE_MINHASHES(bins, q2_cache)
        distance_matrix = COMPARE_MINHASHES(minhashes, q2_cache)
        DEREPLICATE_MAGS(bins, distance_matrix, q2_cache)
        downstream_bins = DEREPLICATE_MAGS.out.bins_derep

        if (params.dereplication.provenanceCheckpoint) {
            downstream_bins = CHECKPOINT_DEREP_MAGS(downstream_bins).bins_derep
        }

        if (params.dereplication.fetchArtifact) {
            FETCH_ARTIFACT_MAGS_DEREP(DEREPLICATE_MAGS.out.bins_derep)
        }
    emit:
        bins_derep = downstream_bins
        feature_table = DEREPLICATE_MAGS.out.feature_table
}
