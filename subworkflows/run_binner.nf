include { BIN_CONTIGS_METABAT; BIN_CONTIGS_SEMIBIN2; BIN_CONTIGS_VAMB; SUMMARIZE_BINNING } from '../modules/contig_binning'
include { BINNING_QC } from './binning_qc'

workflow RUN_BINNER {
    take:
        binner
        contigs
        maps
        q2_cache
        with_busco
        busco_db
    main:
        contigs_with_maps = contigs.join(maps)
        if (binner == 'metabat2') {
            bin_out = BIN_CONTIGS_METABAT(contigs_with_maps)
            unbinned = bin_out.unbinned_contigs
        } else if (binner == 'semibin2') {
            bin_out = BIN_CONTIGS_SEMIBIN2(contigs_with_maps)
            unbinned = bin_out.unbinned_contigs
        } else if (binner == 'vamb') {
            bin_out = BIN_CONTIGS_VAMB(contigs_with_maps)
            summary = SUMMARIZE_BINNING(binner, contigs.join(bin_out.bins))
            unbinned = summary.unbinned_contigs
        } else {
            error "Unknown binner: ${binner}"
        }
        qc = BINNING_QC(binner, bin_out.bins, bin_out.contig_map, unbinned, q2_cache, with_busco, busco_db)
    emit:
        raw_bins = bin_out.bins
        bins = qc.bins
        contig_map = qc.contig_map
        contig_map_collated = qc.contig_map_collated
        unbinned_contigs = qc.unbinned_contigs
        busco_results = qc.busco_results
        bins_collated = qc.bins_collated
        completion = qc.completion
        qzv = qc.qzv
}
