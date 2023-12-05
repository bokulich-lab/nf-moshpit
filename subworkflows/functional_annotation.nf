include { SEARCH_ORTHOLOGS_EGGNOG as SEARCH_ORTHOLOGS_MAGS; SEARCH_ORTHOLOGS_EGGNOG as SEARCH_ORTHOLOGS_CONTIGS } from '../modules/functional_annotation'
include { ANNOTATE_EGGNOG as ANNOTATE_MAGS; ANNOTATE_EGGNOG as ANNOTATE_CONTIGS } from '../modules/functional_annotation'

workflow ANNOTATE_EGGNOG_MAGS {
    take:
        mags
    main:
        orthologs = SEARCH_ORTHOLOGS_MAGS(mags, "mags")
        annotations = ANNOTATE_MAGS(SEARCH_ORTHOLOGS_MAGS.out.hits, "mags")
}

workflow ANNOTATE_EGGNOG_CONTIGS {
    take:
        contigs
    main:
        orthologs = SEARCH_ORTHOLOGS_CONTIGS(contigs, "contigs")
        annotations = ANNOTATE_CONTIGS(SEARCH_ORTHOLOGS_CONTIGS.out.hits, "contigs")
}
