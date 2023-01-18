include { CLASSIFY_BINS_KRAKEN2 } from '../modules/taxonomic_classification'
include { CLASSIFY_READS_KRAKEN2 } from '../modules/taxonomic_classification'
include { DRAW_TAXA_BARPLOT } from '../modules/taxonomic_classification'

workflow CLASSIFY_BINS {
    take:
        bins
    main:
        classification = CLASSIFY_BINS_KRAKEN2(bins)
//         DRAW_TAXA_BARPLOT(classification.table, classification.taxonomy)
}

workflow CLASSIFY_READS {
    take:
        seqs
    main:
        classification = CLASSIFY_READS_KRAKEN2(seqs)
//         DRAW_TAXA_BARPLOT(classification.table, classification.taxonomy)
}
