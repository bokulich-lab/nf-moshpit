include { effectivePrimaryBinner; evaluateBinnerBusco } from '../modules/binning_policy'
include { FETCH_BUSCO_DB; REFINE_BINS_DAS_TOOL; SUMMARIZE_BINNING as SUMMARIZE_DAS_TOOL } from '../modules/contig_binning'
include { RUN_BINNER as RUN_BINNER_METABAT2; RUN_BINNER as RUN_BINNER_SEMIBIN2; RUN_BINNER as RUN_BINNER_VAMB } from './run_binner'
include { BINNING_QC as DAS_TOOL_QC } from './binning_qc'

workflow BINNING {
    take:
        contigs
        maps
        q2_cache
    main:
        qzv_outputs = Channel.empty()
        completion = Channel.empty()
        candidates = Channel.empty()
        results = [:]
        enabled = ['metabat2', 'semibin2', 'vamb'].findAll { params.binning[it].enabled }
        busco_db = params.binning.qc.busco.enabled ? FETCH_BUSCO_DB().result : Channel.empty()

        if (params.binning.metabat2.enabled) {
            results.metabat2 = RUN_BINNER_METABAT2('metabat2', contigs, maps, q2_cache, evaluateBinnerBusco(params.binning), busco_db)
            candidates = candidates.mix(results.metabat2.raw_bins.map { id, key -> tuple(id, 'metabat2', key.name) })
            qzv_outputs = qzv_outputs.mix(results.metabat2.qzv)
            completion = completion.mix(results.metabat2.completion)
        }
        if (params.binning.semibin2.enabled) {
            results.semibin2 = RUN_BINNER_SEMIBIN2('semibin2', contigs, maps, q2_cache, evaluateBinnerBusco(params.binning), busco_db)
            candidates = candidates.mix(results.semibin2.raw_bins.map { id, key -> tuple(id, 'semibin2', key.name) })
            qzv_outputs = qzv_outputs.mix(results.semibin2.qzv)
            completion = completion.mix(results.semibin2.completion)
        }
        if (params.binning.vamb.enabled) {
            results.vamb = RUN_BINNER_VAMB('vamb', contigs, maps, q2_cache, evaluateBinnerBusco(params.binning), busco_db)
            candidates = candidates.mix(results.vamb.raw_bins.map { id, key -> tuple(id, 'vamb', key.name) })
            qzv_outputs = qzv_outputs.mix(results.vamb.qzv)
            completion = completion.mix(results.vamb.completion)
        }
        if (params.binning.das_tool.enabled) {
            // Ignored no-bin samples may differ across binners. Refine only the
            // intersection, preserving deterministic label/input ordering.
            complete_candidates = candidates.groupTuple()
                .filter { id, labels, keys ->
                    if (labels.size() != enabled.size()) {
                        log.warn "Skipping DAS Tool for ${id}: bins missing from ${enabled - labels}"
                        return false
                    }
                    true
                }
                .map { id, labels, keys ->
                    def ordered = [labels, keys].transpose().sort { it[0] }
                    tuple(id, ordered.collect { it[1] }, ordered.collect { it[0] }.join(','))
                }
                .join(contigs)
            refined = REFINE_BINS_DAS_TOOL(complete_candidates)
            summary = SUMMARIZE_DAS_TOOL('das_tool', contigs.join(refined.bins))
            results.das_tool = DAS_TOOL_QC('das_tool', refined.bins, summary.contig_map, summary.unbinned_contigs, q2_cache, params.binning.qc.busco.enabled, busco_db)
            qzv_outputs = qzv_outputs.mix(results.das_tool.qzv)
            completion = completion.mix(results.das_tool.completion).mix(refined.summary).mix(refined.input_bins_evaluation)
        }
        selected = results[effectivePrimaryBinner(params.binning)]
    emit:
        bins = selected.bins
        contig_map = selected.contig_map
        contig_map_collated = selected.contig_map_collated
        unbinned_contigs = selected.unbinned_contigs
        busco_results = selected.busco_results
        bins_collated = selected.bins_collated
        completion = completion
        qzv = qzv_outputs
}
