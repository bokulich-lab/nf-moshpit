include { FETCH_BUSCO_DB } from '../modules/contig_binning'
include { RUN_BINNER as RUN_BINNER_METABAT2 } from './run_binner'
include { RUN_BINNER as RUN_BINNER_SEMIBIN2 } from './run_binner'

workflow BINNING {
    take:
        contigs
        maps
        q2_cache

    main:
        qzv_outputs = Channel.empty()

        if (params.binning.qc.busco.enabled) {
            busco_db = FETCH_BUSCO_DB()
        } else {
            busco_db = Channel.empty()
        }

        if (params.binning.metabat2.enabled) {
            metabat2_results = RUN_BINNER_METABAT2(
                'metabat2',
                contigs,
                maps,
                q2_cache,
                params.binning.qc.busco.enabled,
                busco_db
            )
            qzv_outputs = qzv_outputs.mix(metabat2_results.qzv)
        }

        if (params.binning.semibin2.enabled) {
            semibin2_results = RUN_BINNER_SEMIBIN2(
                'semibin2',
                contigs,
                maps,
                q2_cache,
                params.binning.qc.busco.enabled,
                busco_db
            )
            qzv_outputs = qzv_outputs.mix(semibin2_results.qzv)
        }

        if (params.binning.primary == 'metabat2') {
            selected = metabat2_results
        } else {
            selected = semibin2_results
        }

    emit:
        bins = selected.bins
        contig_map = selected.contig_map
        unbinned_contigs = selected.unbinned_contigs
        busco_results = selected.busco_results
        bins_collated = selected.bins_collated
        qzv = qzv_outputs
}
