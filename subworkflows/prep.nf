include { FETCH_GENOMES } from '../modules/data_prep'
include { FETCH_SEQS } from '../modules/data_prep'
include { SIMULATE_READS } from '../modules/data_prep'
include { SUBSAMPLE_READS } from '../modules/data_prep'
include { SUMMARIZE_READS; SUMMARIZE_READS as SUMMARIZE_TRIMMED } from '../modules/data_prep'
include { REMOVE_HOST } from '../modules/data_prep'
include { TRIM_READS } from '../modules/data_prep'
include { CACHE_STORE } from '../modules/qiime_cache'

workflow PREPARE_DATA {
    main:
        // prepare input reads
        if (params.inputReads) {
            reads = params.inputReads
        } else if (params.fondue.filesAccessionIds) {
            ids = Channel.fromPath(params.fondue.filesAccessionIds)
            fetched_reads = FETCH_SEQS(ids)
            reads = (params.fondue.paired) ? fetched_reads.paired : fetched_reads.single
        } else if (params.read_simulation.sampleGenomes) {
            genomes = Channel.fromPath(params.read_simulation.sampleGenomes)
            simulated_reads = SIMULATE_READS(genomes)
            reads = simulated_reads.reads
        } else {
            genomes = FETCH_GENOMES()
            simulated_reads = SIMULATE_READS(genomes)
            reads = simulated_reads.reads
        }

        // subsample reads
        if (params.read_subsampling.enabled) {
            reads = SUBSAMPLE_READS(reads)
        }

        // perform read QC
        SUMMARIZE_READS(reads, "raw", params.q2keyRawReads)

        // trim reads
        if (params.read_trimming.enabled) {
            q2key = (params.read_subsampling.enabled) ? "" : params.q2keyRawReads
            reads = TRIM_READS(reads, q2key)

            // repeat read QC
            SUMMARIZE_TRIMMED(reads, "trimmed", "")
        }

        // remove host reads
        if (params.host_removal.enabled) {
            reads = REMOVE_HOST(reads)
        }

        // save final reads to cache, if required
        if (params.read_subsampling.enabled || params.read_trimming.enabled || params.host_removal.enabled) {
            reads = CACHE_STORE(reads, params.q2keyPreprocessedReads)
        }
        
    emit:
        reads
}
