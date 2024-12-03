include { SEARCH_ORTHOLOGS_EGGNOG as SEARCH_ORTHOLOGS_MAGS_DEREP; SEARCH_ORTHOLOGS_EGGNOG as SEARCH_ORTHOLOGS_CONTIGS; SEARCH_ORTHOLOGS_EGGNOG as SEARCH_ORTHOLOGS_MAGS } from '../modules/functional_annotation'
include { ANNOTATE_EGGNOG as ANNOTATE_MAGS_DEREP; ANNOTATE_EGGNOG as ANNOTATE_CONTIGS; ANNOTATE_EGGNOG as ANNOTATE_MAGS } from '../modules/functional_annotation'

workflow ANNOTATE_EGGNOG_MAGS {
    take:
        mags_derep
        diamond_db
        eggnog_db
        q2_cache
    main:
        orthologs = SEARCH_ORTHOLOGS_MAGS(mags_derep, diamond_db, "mags", q2_cache)
        annotations = ANNOTATE_MAGS(SEARCH_ORTHOLOGS_MAGS.out.hits, eggnog_db, "mags", q2_cache)
}

workflow ANNOTATE_EGGNOG_MAGS_DEREP {
    take:
        mags_derep
        diamond_db
        eggnog_db
        q2_cache
    main:
        orthologs = SEARCH_ORTHOLOGS_MAGS_DEREP(mags_derep, diamond_db, "mags_derep", q2_cache)
        annotations = ANNOTATE_MAGS_DEREP(SEARCH_ORTHOLOGS_MAGS_DEREP.out.hits, eggnog_db, "mags_derep", q2_cache)
}

workflow ANNOTATE_EGGNOG_CONTIGS {
    take:
        contigs
        diamond_db
        eggnog_db
        q2_cache
    main:
        orthologs = SEARCH_ORTHOLOGS_CONTIGS(contigs, diamond_db, "contigs", q2_cache)
        annotations = ANNOTATE_CONTIGS(SEARCH_ORTHOLOGS_CONTIGS.out.hits, eggnog_db, "contigs", q2_cache)
}
