include { CLASSIFY_KRAKEN2 as CLASSIFY_READS_KRAKEN2; CLASSIFY_KRAKEN2 as CLASSIFY_CONTIGS_KRAKEN2; CLASSIFY_KRAKEN2 as CLASSIFY_MAGS_KRAKEN2; CLASSIFY_KRAKEN2 as CLASSIFY_MAGS_DEREP_KRAKEN2 } from '../modules/taxonomic_classification'
include { ESTIMATE_BRACKEN } from '../modules/taxonomic_classification'
include { GET_KRAKEN_FEATURES; GET_KRAKEN_FEATURES as GET_KRAKEN_MAG_DEREP_FEATURES } from '../modules/taxonomic_classification'
include { DRAW_TAXA_BARPLOT } from '../modules/taxonomic_classification'
include { COLLATE_PARTITIONS as COLLATE_REPORTS_READS } from '../modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_HITS_READS } from '../modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_REPORTS_MAGS } from '../modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_HITS_MAGS } from '../modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_REPORTS_MAGS_DEREP } from '../modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_HITS_MAGS_DEREP } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_REPORTS } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_HITS } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_FT } from '../modules/data_prep'

workflow CLASSIFY_MAGS {
    take:
        bins
        kraken2_db
        q2_cache
    main:
        classification = CLASSIFY_MAGS_KRAKEN2(bins, kraken2_db, "mags", q2_cache)

        // collate reports and hits
        reports_all = CLASSIFY_MAGS_KRAKEN2.out.reports | map { _id, _key -> _key } | collect
        hits_all = CLASSIFY_MAGS_KRAKEN2.out.hits | map { _id, _key -> _key } | collect
        collated_reports = COLLATE_REPORTS_MAGS(reports_all, "kraken_reports_mags", "moshpit collate-kraken2-reports", "--i-kraken2-reports", "--o-collated-kraken2-reports", true)
        collated_hits = COLLATE_HITS_MAGS(hits_all, "kraken_outputs_mags", "moshpit collate-kraken2-outputs", "--i-kraken2-outputs", "--o-collated-kraken2-outputs", true)
        if (params.taxonomic_classification.fetchArtifact) {
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
        bins = bins.map { bin -> ["mags-derep", bin] }
        CLASSIFY_MAGS_DEREP_KRAKEN2(bins, kraken2_db, "mags-derep", q2_cache)

        reports = CLASSIFY_MAGS_DEREP_KRAKEN2.out.reports | map { _id, report -> report }
        hits = CLASSIFY_MAGS_DEREP_KRAKEN2.out.hits | map { _id, hit -> hit }

        if (params.taxonomic_classification.fetchArtifact) {
            FETCH_ARTIFACT_REPORTS(reports)
            FETCH_ARTIFACT_HITS(hits)
        }

        GET_KRAKEN_MAG_DEREP_FEATURES(reports, hits, "mags_derep")
}

workflow CLASSIFY_READS {
    take:
        reads
        kraken2_db
        bracken_db
        q2_cache
    main:
        classification = CLASSIFY_READS_KRAKEN2(reads, kraken2_db, "reads", q2_cache)

        // collate reports and hits
        reports_all = CLASSIFY_READS_KRAKEN2.out.reports | map { _id, _key -> _key } | collect
        hits_all = CLASSIFY_READS_KRAKEN2.out.hits | map { _id, _key -> _key } | collect
        reports_all = COLLATE_REPORTS_READS(reports_all, "kraken_reports_reads", "moshpit collate-kraken2-reports", "--i-kraken2-reports", "--o-collated-kraken2-reports", true)
        hits_all = COLLATE_HITS_READS(hits_all, "kraken_outputs_reads", "moshpit collate-kraken2-outputs", "--i-kraken2-outputs", "--o-collated-kraken2-outputs", true)

        if (params.taxonomic_classification.bracken.enabled) {
            ESTIMATE_BRACKEN(reports_all, bracken_db, q2_cache)
            DRAW_TAXA_BARPLOT(ESTIMATE_BRACKEN.out.feature_table, ESTIMATE_BRACKEN.out.taxonomy, "bracken")
            if (params.taxonomic_classification.fetchArtifact) {
                FETCH_ARTIFACT_FT(ESTIMATE_BRACKEN.out.feature_table)
            }
        } else {
            GET_KRAKEN_FEATURES(reports_all, hits_all, "reads")
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
        classification = CLASSIFY_CONTIGS_KRAKEN2(contigs, kraken2_db, "contigs", q2_cache)

        // collate reports and hits
        reports_all = CLASSIFY_CONTIGS_KRAKEN2.out.reports | map { _id, _key -> _key } | collect
        hits_all = CLASSIFY_CONTIGS_KRAKEN2.out.hits | map { _id, _key -> _key } | collect
        reports_all = COLLATE_REPORTS_READS(reports_all, "kraken_reports_contigs", "moshpit collate-kraken2-reports", "--i-kraken2-reports", "--o-collated-kraken2-reports", true)
        hits_all = COLLATE_HITS_READS(hits_all, "kraken_outputs_contigs", "moshpit collate-kraken2-outputs", "--i-kraken2-outputs", "--o-collated-kraken2-outputs", true)

        if (params.taxonomic_classification.fetchArtifact) {
            FETCH_ARTIFACT_REPORTS(reports_all)
            FETCH_ARTIFACT_HITS(hits_all)
        }
}
