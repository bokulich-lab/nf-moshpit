include { SEARCH_ORTHOLOGS_EGGNOG as SEARCH_ORTHOLOGS_MAGS; SEARCH_ORTHOLOGS_EGGNOG as SEARCH_ORTHOLOGS_CONTIGS } from '../modules/functional_annotation'
include { ANNOTATE_EGGNOG as ANNOTATE_MAGS; ANNOTATE_EGGNOG as ANNOTATE_CONTIGS } from '../modules/functional_annotation'

workflow ANNOTATE_EGGNOG_MAGS {
    take:
        mags
        q2_cache
    main:
        orthologs = SEARCH_ORTHOLOGS_MAGS(mags, "mags", q2_cache)
        annotations = ANNOTATE_MAGS(SEARCH_ORTHOLOGS_MAGS.out.hits, "mags")
}

workflow ANNOTATE_EGGNOG_CONTIGS {
    take:
        contigs
        q2_cache
    main:
        orthologs = SEARCH_ORTHOLOGS_CONTIGS(contigs, "contigs", q2_cache)
        annotations = ANNOTATE_CONTIGS(SEARCH_ORTHOLOGS_CONTIGS.out.hits, "contigs")
}
