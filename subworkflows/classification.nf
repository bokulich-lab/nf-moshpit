include { CLASSIFY_KRAKEN2 as CLASSIFY_READS_KRAKEN2; CLASSIFY_KRAKEN2 as CLASSIFY_CONTIGS_KRAKEN2; CLASSIFY_KRAKEN2 as CLASSIFY_MAGS_KRAKEN2 } from '../modules/taxonomic_classification'
include { CLASSIFY_KRAKEN2_DEREP as CLASSIFY_MAGS_DEREP_KRAKEN2 } from '../modules/taxonomic_classification'
include { CLASSIFY_KAIJU as CLASSIFY_KAIJU_READS } from '../modules/taxonomic_classification'
include { CLASSIFY_KAIJU as CLASSIFY_KAIJU_CONTIGS } from '../modules/taxonomic_classification'
include { ESTIMATE_BRACKEN } from '../modules/taxonomic_classification'
include { GET_KRAKEN_FEATURES; GET_KRAKEN_FEATURES as GET_KRAKEN_MAG_DEREP_FEATURES } from '../modules/taxonomic_classification'
include { DRAW_TAXA_BARPLOT; DRAW_TAXA_BARPLOT as DRAW_TAXA_BARPLOT_KAIJU_READS } from '../modules/taxonomic_classification'
include { COLLATE_PARTITIONS as COLLATE_REPORTS_READS } from '../modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_HITS_READS } from '../modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_REPORTS_MAGS } from '../modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_HITS_MAGS } from '../modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_REPORTS_MAGS_DEREP } from '../modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_HITS_MAGS_DEREP } from '../modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_FT } from '../modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_FT_CONTIGS } from '../modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_TAXONOMY_CONTIGS } from '../modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_TAXONOMY } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_REPORTS } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_HITS } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_FT; FETCH_ARTIFACT as FETCH_ARTIFACT_PA } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_KAIJU_FT_READS; FETCH_ARTIFACT as FETCH_ARTIFACT_KAIJU_TAXONOMY_READS } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_KAIJU_FT_CONTIGS; FETCH_ARTIFACT as FETCH_ARTIFACT_KAIJU_TAXONOMY_CONTIGS } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_BRACKEN_TAXONOMY; FETCH_ARTIFACT as FETCH_ARTIFACT_KRAKEN2_TAXONOMY; FETCH_ARTIFACT as FETCH_ARTIFACT_BRACKEN_REPORTS } from '../modules/data_prep'

workflow CLASSIFY_MAGS {
    take:
        bins
        kraken2_db
        q2_cache
    main:
        classification = CLASSIFY_MAGS_KRAKEN2(bins, kraken2_db, "mags")

        // collate reports and hits
        reports_all = CLASSIFY_MAGS_KRAKEN2.out.reports | collect(flat: false)
        hits_all = CLASSIFY_MAGS_KRAKEN2.out.hits | collect(flat: false)
        collated_reports = COLLATE_REPORTS_MAGS(reports_all, "${params.runId}_kraken_reports_mags_${params.binning.qc.busco.selectLineage}", "annotate collate-kraken2-reports", "--i-reports", "--o-collated-reports", true)
        collated_hits = COLLATE_HITS_MAGS(hits_all, "${params.runId}_kraken_outputs_mags_${params.binning.qc.busco.selectLineage}", "annotate collate-kraken2-outputs", "--i-outputs", "--o-collated-outputs", true)
        if (params.taxonomic_classification.kraken2.fetchArtifact) {
            FETCH_ARTIFACT_REPORTS(collated_reports)
            FETCH_ARTIFACT_HITS(collated_hits)
        }
}

workflow CLASSIFY_MAGS_DEREP {
    take:
        bins
        kraken2_db
        q2_cache
    main:
        CLASSIFY_MAGS_DEREP_KRAKEN2(bins, kraken2_db, q2_cache)

        if (params.taxonomic_classification.kraken2.fetchArtifact) {
            FETCH_ARTIFACT_REPORTS(CLASSIFY_MAGS_DEREP_KRAKEN2.out.reports)
            FETCH_ARTIFACT_HITS(CLASSIFY_MAGS_DEREP_KRAKEN2.out.hits)
        }

        GET_KRAKEN_MAG_DEREP_FEATURES(CLASSIFY_MAGS_DEREP_KRAKEN2.out.reports, CLASSIFY_MAGS_DEREP_KRAKEN2.out.hits, "mags_derep")
        if (params.taxonomic_classification.fetchArtifact) {
            FETCH_ARTIFACT_KRAKEN2_TAXONOMY(GET_KRAKEN_MAG_DEREP_FEATURES.out.taxonomy)
        }
}

workflow CLASSIFY_READS {
    take:
        reads
        kraken2_db
        bracken_db
        q2_cache
    main:
        classification = CLASSIFY_READS_KRAKEN2(reads, kraken2_db, "reads")

        reports_all = CLASSIFY_READS_KRAKEN2.out.reports | collect(flat: false)
        hits_all = CLASSIFY_READS_KRAKEN2.out.hits | collect(flat: false)
        reports_all = COLLATE_REPORTS_READS(reports_all, "${params.runId}_kraken_reports_reads", "annotate collate-kraken2-reports", "--i-reports", "--o-collated-reports", true)
        hits_all = COLLATE_HITS_READS(hits_all, "${params.runId}_kraken_outputs_reads", "annotate collate-kraken2-outputs", "--i-outputs", "--o-collated-outputs", true)

        if (params.taxonomic_classification.bracken.enabled) {
            ESTIMATE_BRACKEN(reports_all, bracken_db, q2_cache)
            DRAW_TAXA_BARPLOT(ESTIMATE_BRACKEN.out.feature_table, ESTIMATE_BRACKEN.out.taxonomy, "bracken")
            if (params.taxonomic_classification.fetchArtifact) {
                FETCH_ARTIFACT_FT(ESTIMATE_BRACKEN.out.feature_table)
                FETCH_ARTIFACT_BRACKEN_TAXONOMY(ESTIMATE_BRACKEN.out.taxonomy)
            }
            if (params.taxonomic_classification.bracken.fetchArtifact) {
                FETCH_ARTIFACT_BRACKEN_REPORTS(ESTIMATE_BRACKEN.out.reports)
            }
        } else {
            GET_KRAKEN_FEATURES(reports_all, hits_all, "reads")
            if (params.taxonomic_classification.fetchArtifact) {
                FETCH_ARTIFACT_TAXONOMY_KRAKEN2(GET_KRAKEN_FEATURES.out.features)
                FETCH_ARTIFACT_PA(GET_KRAKEN_FEATURES.out.feature_table)
            }
        }

        if (params.taxonomic_classification.fetchArtifact) {
            FETCH_ARTIFACT_REPORTS(reports_all)
            FETCH_ARTIFACT_HITS(hits_all)
        }
}

workflow CLASSIFY_CONTIGS {
    take:
        contigs
        kraken2_db
        q2_cache
    main:
        classification = CLASSIFY_CONTIGS_KRAKEN2(contigs, kraken2_db, "contigs")

        reports_all = CLASSIFY_CONTIGS_KRAKEN2.out.reports | collect(flat: false)
        hits_all = CLASSIFY_CONTIGS_KRAKEN2.out.hits | collect(flat: false)
        reports_all = COLLATE_REPORTS_READS(reports_all, "${params.runId}_kraken_reports_contigs", "annotate collate-kraken2-reports", "--i-reports", "--o-collated-reports", true)
        hits_all = COLLATE_HITS_READS(hits_all, "${params.runId}_kraken_outputs_contigs", "annotate collate-kraken2-outputs", "--i-outputs", "--o-collated-outputs", true)

        if (params.taxonomic_classification.kraken2.fetchArtifact) {
            FETCH_ARTIFACT_REPORTS(reports_all)
            FETCH_ARTIFACT_HITS(hits_all)
        }
}

workflow CLASSIFY_READS_KAIJU {
    take:
        reads
        kaiju_db
        q2_cache
    main:
        classification = CLASSIFY_KAIJU_READS(reads, kaiju_db, "reads")

        ft_all = CLASSIFY_KAIJU_READS.out.feature_table | collect(flat: false)
        taxonomy_all = CLASSIFY_KAIJU_READS.out.taxonomy | collect(flat: false)
        ft_all = COLLATE_FT(ft_all, "${params.runId}_kaiju_feature_table_reads", "feature-table merge", "--i-tables", "--o-merged-table", true)
        taxonomy_all = COLLATE_TAXONOMY(taxonomy_all, "${params.runId}_kaiju_taxonomy_reads", "feature-table merge-taxa", "--i-data", "--o-merged-data", true)
        DRAW_TAXA_BARPLOT_KAIJU_READS(ft_all, taxonomy_all, "kaiju-reads")

        if (params.taxonomic_classification.fetchArtifact) {
            FETCH_ARTIFACT_KAIJU_FT_READS(ft_all)
            FETCH_ARTIFACT_KAIJU_TAXONOMY_READS(taxonomy_all)
        }
}

workflow CLASSIFY_CONTIGS_KAIJU {
    take:
        contigs
        kaiju_db
        q2_cache
    main:
        classification = CLASSIFY_KAIJU_CONTIGS(contigs, kaiju_db, "contigs")

        ft_all = CLASSIFY_KAIJU_CONTIGS.out.feature_table | collect(flat: false)
        taxonomy_all = CLASSIFY_KAIJU_CONTIGS.out.taxonomy | collect(flat: false)
        ft_all = COLLATE_FT_CONTIGS(ft_all, "${params.runId}_kaiju_feature_table_contigs", "feature-table merge", "--i-tables", "--o-merged-table", true)
        taxonomy_all = COLLATE_TAXONOMY_CONTIGS(taxonomy_all, "${params.runId}_kaiju_taxonomy_contigs", "feature-table merge-taxa", "--i-data", "--o-merged-data", true)

        if (params.taxonomic_classification.fetchArtifact) {
            FETCH_ARTIFACT_KAIJU_FT_CONTIGS(ft_all)
            FETCH_ARTIFACT_KAIJU_TAXONOMY_CONTIGS(taxonomy_all)
        }
}
