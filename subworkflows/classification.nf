include { CLASSIFY_KRAKEN2 as CLASSIFY_READS_KRAKEN2; CLASSIFY_KRAKEN2 as CLASSIFY_MAGS_KRAKEN2 } from '../modules/taxonomic_classification'
include { ESTIMATE_BRACKEN } from '../modules/taxonomic_classification'
include { GET_KRAKEN_FEATURES; GET_KRAKEN_FEATURES as GET_KRAKEN_MAG_FEATURES } from '../modules/taxonomic_classification'
include { DRAW_TAXA_BARPLOT } from '../modules/taxonomic_classification'

workflow CLASSIFY_MAGS {
    take:
        bins
    main:
        classification = CLASSIFY_MAGS_KRAKEN2(bins, "mags")
        kraken_features = GET_KRAKEN_MAG_FEATURES(CLASSIFY_MAGS_KRAKEN2.out.reports, CLASSIFY_MAGS_KRAKEN2.out.hits, "mags")
        // DRAW_TAXA_BARPLOT(CLASSIFY_MAGS_KRAKEN2.out.table, CLASSIFY_MAGS_KRAKEN2.out.taxonomy)
}

workflow CLASSIFY_READS {
    take:
        seqs
    main:
        classification = CLASSIFY_READS_KRAKEN2(seqs, "reads")
        if (params.taxonomic_classification.bracken.enabled) {
            bracken_results = ESTIMATE_BRACKEN(classification.reports)
            DRAW_TAXA_BARPLOT(ESTIMATE_BRACKEN.out.feature_table, ESTIMATE_BRACKEN.out.taxonomy, "bracken")
        } else {
            kraken_features = GET_KRAKEN_FEATURES(CLASSIFY_READS_KRAKEN2.out.reports, CLASSIFY_READS_KRAKEN2.out.hits, "reads")
        }
}
