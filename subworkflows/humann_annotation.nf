include { PROFILE_READS_HUMANN; COLLATE_HUMANN_PARTITIONS as COLLATE_GENE_FAMILIES_READS; COLLATE_HUMANN_PARTITIONS as COLLATE_PATH_ABUNDANCE_READS; COLLATE_HUMANN_PARTITIONS as COLLATE_METAPHLAN_PROFILES_READS; COLLATE_HUMANN_PARTITIONS as COLLATE_REACTIONS_READS; CONVERT_HUMANN_GENE_FAMILIES; CONVERT_HUMANN_PATH_ABUNDANCE; CONVERT_METAPHLAN_PROFILE; FETCH_HUMANN_ARTIFACT } from '../modules/humann_annotation'
include { DRAW_TAXA_BARPLOT as DRAW_TAXA_BARPLOT_HUMANN_GENE_FAMILIES; DRAW_TAXA_BARPLOT as DRAW_TAXA_BARPLOT_HUMANN_PATH_ABUNDANCE } from '../modules/taxonomic_classification'
// DRAW_TAXA_BARPLOT_HUMANN_METAPHLAN import removed - see comment below where it was used
include { FETCH_ARTIFACT as FETCH_ARTIFACT_GENE_FAMILIES_FT } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_GENE_FAMILIES_TAX } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_PATH_ABUNDANCE_FT } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_PATH_ABUNDANCE_TAX } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_METAPHLAN_FT } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_METAPHLAN_TAX } from '../modules/data_prep'

workflow ANNOTATE_READS_HUMANN {
    take:
        reads
        chocophlan_db
        translated_search_db
        metaphlan_db
        q2_cache
    main:
        PROFILE_READS_HUMANN(reads, chocophlan_db, translated_search_db, metaphlan_db)

        gene_families_all = PROFILE_READS_HUMANN.out.gene_families | collect(flat: false)
        path_abundance_all = PROFILE_READS_HUMANN.out.path_abundance | collect(flat: false)
        metaphlan_profiles_all = PROFILE_READS_HUMANN.out.metaphlan_profile | collect(flat: false)
        reactions_all = PROFILE_READS_HUMANN.out.reactions | collect(flat: false)

        collated_gene_families = COLLATE_GENE_FAMILIES_READS(
            gene_families_all,
            "${params.runId}_humann_gene_families_reads",
            "humann3 collate-gene-families",
            "--i-tables",
            "--o-collated-table",
            true
        )
        collated_path_abundance = COLLATE_PATH_ABUNDANCE_READS(
            path_abundance_all,
            "${params.runId}_humann_path_abundance_reads",
            "humann3 collate-path-abundance",
            "--i-tables",
            "--o-collated-table",
            true
        )
        collated_metaphlan_profiles = COLLATE_METAPHLAN_PROFILES_READS(
            metaphlan_profiles_all,
            "${params.runId}_humann_metaphlan_profiles_reads",
            "humann3 collate-metaphlan-profiles",
            "--i-tables",
            "--o-collated-table",
            true
        )
        collated_reactions = COLLATE_REACTIONS_READS(
            reactions_all,
            "${params.runId}_humann_reactions_reads",
            "humann3 collate-reactions",
            "--i-tables",
            "--o-collated-table",
            true
        )

        qzv_outputs = Channel.empty()

        CONVERT_HUMANN_GENE_FAMILIES(collated_gene_families, q2_cache)
        CONVERT_HUMANN_PATH_ABUNDANCE(collated_path_abundance, q2_cache)
        CONVERT_METAPHLAN_PROFILE(collated_metaphlan_profiles, q2_cache)

        DRAW_TAXA_BARPLOT_HUMANN_GENE_FAMILIES(CONVERT_HUMANN_GENE_FAMILIES.out.feature_table, CONVERT_HUMANN_GENE_FAMILIES.out.taxonomy, "humann-gene-families")
        DRAW_TAXA_BARPLOT_HUMANN_PATH_ABUNDANCE(CONVERT_HUMANN_PATH_ABUNDANCE.out.feature_table, CONVERT_HUMANN_PATH_ABUNDANCE.out.taxonomy, "humann-path-abundance")
        // MetaPhlAn's feature table is a RelativeFrequency table, which "qiime taxa barplot" cannot render
        // (only the experimental "barplot2" supports RelativeFrequency). Disabled until we have a proper fix.
        // DRAW_TAXA_BARPLOT_HUMANN_METAPHLAN(CONVERT_METAPHLAN_PROFILE.out.feature_table, CONVERT_METAPHLAN_PROFILE.out.taxonomy, "humann-metaphlan")
        qzv_outputs = qzv_outputs.mix(DRAW_TAXA_BARPLOT_HUMANN_GENE_FAMILIES.out.qzv)
        qzv_outputs = qzv_outputs.mix(DRAW_TAXA_BARPLOT_HUMANN_PATH_ABUNDANCE.out.qzv)
        // qzv_outputs = qzv_outputs.mix(DRAW_TAXA_BARPLOT_HUMANN_METAPHLAN.out.qzv)

        if (params.humann3.fetchArtifact) {
            FETCH_ARTIFACT_GENE_FAMILIES_FT(CONVERT_HUMANN_GENE_FAMILIES.out.feature_table)
            FETCH_ARTIFACT_GENE_FAMILIES_TAX(CONVERT_HUMANN_GENE_FAMILIES.out.taxonomy)
            FETCH_ARTIFACT_PATH_ABUNDANCE_FT(CONVERT_HUMANN_PATH_ABUNDANCE.out.feature_table)
            FETCH_ARTIFACT_PATH_ABUNDANCE_TAX(CONVERT_HUMANN_PATH_ABUNDANCE.out.taxonomy)
            FETCH_ARTIFACT_METAPHLAN_FT(CONVERT_METAPHLAN_PROFILE.out.feature_table)
            FETCH_ARTIFACT_METAPHLAN_TAX(CONVERT_METAPHLAN_PROFILE.out.taxonomy)
            FETCH_HUMANN_ARTIFACT(collated_reactions)
        }
    emit:
        gene_families = CONVERT_HUMANN_GENE_FAMILIES.out.feature_table
        path_abundance = CONVERT_HUMANN_PATH_ABUNDANCE.out.feature_table
        metaphlan_profile = CONVERT_METAPHLAN_PROFILE.out.feature_table
        reactions = collated_reactions
        qzv = qzv_outputs
}
