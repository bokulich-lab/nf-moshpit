include { CLASSIFY_KRAKEN2 as CLASSIFY_READS_KRAKEN2; CLASSIFY_KRAKEN2 as CLASSIFY_CONTIGS_KRAKEN2; CLASSIFY_KRAKEN2 as CLASSIFY_MAGS_KRAKEN2 } from '../modules/taxonomic_classification'
include { CLASSIFY_KRAKEN2_DEREP as CLASSIFY_MAGS_DEREP_KRAKEN2 } from '../modules/taxonomic_classification'
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

include { getDirectorySizeInGB } from '../modules/utils.nf'

workflow CLASSIFY_MAGS {
    take:
        bins
        kraken2_db
        q2_cache
    main:
        // set dynamic memory parameter
        def dirInfo = getDirectorySizeInGB("${params.databases.kraken2.cache}/keys/${params.databases.kraken2.key}", "${params.databases.kraken2.cache}/data")
        params.taxonomic_classification = params.taxonomic_classification ?: [:]
        params.taxonomic_classification.kraken2 = params.taxonomic_classification.kraken2 ?: [:]
        params.taxonomic_classification.kraken2.memory = dirInfo.sizeInGBRoundedUp
    
        classification = CLASSIFY_MAGS_KRAKEN2(bins, kraken2_db, "mags")

        // collate reports and hits
        reports_all = CLASSIFY_MAGS_KRAKEN2.out.reports | collect(flat: false)
        hits_all = CLASSIFY_MAGS_KRAKEN2.out.hits | collect(flat: false)
        collated_reports = COLLATE_REPORTS_MAGS(reports_all, "${params.runId}_kraken_reports_mags", "annotate collate-kraken2-reports", "--i-reports", "--o-collated-reports", true)
        collated_hits = COLLATE_HITS_MAGS(hits_all, "${params.runId}_kraken_outputs_mags", "annotate collate-kraken2-outputs", "--i-outputs", "--o-collated-outputs", true)
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
        // set dynamic memory parameter
        def dirInfo = getDirectorySizeInGB("${params.databases.kraken2.cache}/keys/${params.databases.kraken2.key}", "${params.databases.kraken2.cache}/data")
        params.taxonomic_classification = params.taxonomic_classification ?: [:]
        params.taxonomic_classification.kraken2 = params.taxonomic_classification.kraken2 ?: [:]
        params.taxonomic_classification.kraken2.memory = dirInfo.sizeInGBRoundedUp

        CLASSIFY_MAGS_DEREP_KRAKEN2(bins, kraken2_db, q2_cache)

        if (params.taxonomic_classification.fetchArtifact) {
            FETCH_ARTIFACT_REPORTS(CLASSIFY_MAGS_DEREP_KRAKEN2.out.reports)
            FETCH_ARTIFACT_HITS(CLASSIFY_MAGS_DEREP_KRAKEN2.out.hits)
        }

        GET_KRAKEN_MAG_DEREP_FEATURES(CLASSIFY_MAGS_DEREP_KRAKEN2.out.reports, CLASSIFY_MAGS_DEREP_KRAKEN2.out.hits, "mags_derep")
}

workflow CLASSIFY_READS {
    take:
        reads
        kraken2_db
        bracken_db
        q2_cache
    main:
        // set dynamic memory parameter
        def dirInfo = getDirectorySizeInGB("${params.databases.kraken2.cache}/keys/${params.databases.kraken2.key}", "${params.databases.kraken2.cache}/data")
        params.taxonomic_classification = params.taxonomic_classification ?: [:]
        params.taxonomic_classification.kraken2 = params.taxonomic_classification.kraken2 ?: [:]
        params.taxonomic_classification.kraken2.memory = dirInfo.sizeInGBRoundedUp
        
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
        classification = CLASSIFY_CONTIGS_KRAKEN2(contigs, kraken2_db, "contigs")

        reports_all = CLASSIFY_CONTIGS_KRAKEN2.out.reports | collect(flat: false)
        hits_all = CLASSIFY_CONTIGS_KRAKEN2.out.hits | collect(flat: false)
        reports_all = COLLATE_REPORTS_READS(reports_all, "${params.runId}_kraken_reports_contigs", "annotate collate-kraken2-reports", "--i-reports", "--o-collated-reports", true)
        hits_all = COLLATE_HITS_READS(hits_all, "${params.runId}_kraken_outputs_contigs", "annotate collate-kraken2-outputs", "--i-outputs", "--o-collated-outputs", true)

        if (params.taxonomic_classification.fetchArtifact) {
            FETCH_ARTIFACT_REPORTS(reports_all)
            FETCH_ARTIFACT_HITS(hits_all)
        }
}
