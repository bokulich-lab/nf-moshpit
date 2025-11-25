include { SEARCH_ORTHOLOGS_EGGNOG as SEARCH_ORTHOLOGS_MAGS_DEREP; SEARCH_ORTHOLOGS_EGGNOG as SEARCH_ORTHOLOGS_CONTIGS; SEARCH_ORTHOLOGS_EGGNOG as SEARCH_ORTHOLOGS_MAGS } from '../modules/functional_annotation'
include { ANNOTATE_EGGNOG as ANNOTATE_MAGS_DEREP; ANNOTATE_EGGNOG as ANNOTATE_CONTIGS; ANNOTATE_EGGNOG as ANNOTATE_MAGS } from '../modules/functional_annotation'
include { COLLATE_PARTITIONS as COLLATE_ANNOTATIONS_CONTIGS; COLLATE_PARTITIONS as COLLATE_ANNOTATIONS_MAGS; COLLATE_PARTITIONS_DEREP as COLLATE_ANNOTATIONS_MAGS_DEREP} from '../modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_HITS_CONTIGS; COLLATE_PARTITIONS as COLLATE_HITS_MAGS; COLLATE_PARTITIONS_DEREP as COLLATE_HITS_MAGS_DEREP } from '../modules/data_prep'
include { EXTRACT_ANNOTATIONS } from '../modules/functional_annotation'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_ORTHOLOGS } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_ANNOTATIONS } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_EXTRACTED_ANNOTATIONS } from '../modules/data_prep'
include { CLEAN_UP_CACHES } from '../modules/data_prep'

workflow ANNOTATE_EGGNOG_MAGS {
    take:
        mags
        diamond_db
        eggnog_db
    main:
        SEARCH_ORTHOLOGS_MAGS(mags, diamond_db, "mags")
        ANNOTATE_MAGS(SEARCH_ORTHOLOGS_MAGS.out.hits, eggnog_db, "mags")

        if (params.binning.qc.busco.enabled) {
            orthologs_key = "${params.runId}_eggnog_orthologs_mags_${params.binning.qc.busco.selectLineage}"
            annotations_key = "${params.runId}_eggnog_annotations_mags_${params.binning.qc.busco.selectLineage}"
        } else {
            orthologs_key = "${params.runId}_eggnog_orthologs_mags"
            annotations_key = "${params.runId}_eggnog_annotations_mags"
        }

        collated_orthologs = COLLATE_HITS_MAGS(SEARCH_ORTHOLOGS_MAGS.out.hits | collect(flat: false), orthologs_key, "types collate-orthologs", "--i-orthologs", "--o-collated-orthologs", true)
        collated_annotations = COLLATE_ANNOTATIONS_MAGS(ANNOTATE_MAGS.out.annotations | collect(flat: false), annotations_key, "types collate-ortholog-annotations", "--i-ortholog-annotations", "--o-collated-annotations", true)

        if (params.functional_annotation.ortholog_search.fetchArtifact) {
            FETCH_ARTIFACT_ORTHOLOGS(collated_orthologs)
        }
        if (params.functional_annotation.annotation.fetchArtifact) {
            FETCH_ARTIFACT_ANNOTATIONS(collated_annotations)
        }

}

workflow ANNOTATE_EGGNOG_MAGS_DEREP {
    take:
        mags_derep
        diamond_db
        eggnog_db
        q2_cache
    main:
        mags_derep = mags_derep.map { partition ->
            def path = java.nio.file.Paths.get(partition.toString())
            def filename = path.getFileName().toString()
            def batchId = filename.substring("${params.runId}_mags_derep_partitioned_".length())
            tuple("batch_${batchId}", partition)
        }
        SEARCH_ORTHOLOGS_MAGS_DEREP(mags_derep, diamond_db, "mags_derep")
        ANNOTATE_MAGS_DEREP(SEARCH_ORTHOLOGS_MAGS_DEREP.out.hits, eggnog_db, "mags_derep")

        if (params.binning.qc.busco.enabled) {
            orthologs_key = "${params.runId}_eggnog_orthologs_mags_derep_${params.binning.qc.busco.selectLineage}"
            annotations_key = "${params.runId}_eggnog_annotations_mags_derep_${params.binning.qc.busco.selectLineage}"
        } else {
            orthologs_key = "${params.runId}_eggnog_orthologs_mags_derep"
            annotations_key = "${params.runId}_eggnog_annotations_mags_derep"
        }
        collated_orthologs = COLLATE_HITS_MAGS_DEREP(SEARCH_ORTHOLOGS_MAGS_DEREP.out.hits | collect(flat: false), orthologs_key, "types collate-orthologs", "--i-orthologs", "--o-collated-orthologs", true)
        collated_annotations = COLLATE_ANNOTATIONS_MAGS_DEREP(ANNOTATE_MAGS_DEREP.out.annotations | collect(flat: false), annotations_key, "types collate-ortholog-annotations", "--i-ortholog-annotations", "--o-collated-annotations", true)


        if (params.functional_annotation.cleanUp) {
            CLEAN_UP_CACHES(collated_annotations, "${params.q2TemporaryCachesDir}/mags")
        }

        if (params.functional_annotation.annotation.extract != "") {
            annotation_type = Channel.of(params.functional_annotation.annotation.extract.types.split(","))
            extracted_annotations = EXTRACT_ANNOTATIONS(collated_annotations, annotation_type, "mags_derep", q2_cache)
            if (params.functional_annotation.annotation.extract.fetchArtifact) {
                FETCH_ARTIFACT_EXTRACTED_ANNOTATIONS(extracted_annotations | map { _type, key -> key})
            }
        }

        if (params.functional_annotation.ortholog_search.fetchArtifact) {
            FETCH_ARTIFACT_ORTHOLOGS(collated_orthologs)
        }
        if (params.functional_annotation.annotation.fetchArtifact) {
            FETCH_ARTIFACT_ANNOTATIONS(collated_annotations)
        }
    emit:
        extracted_annotations

}

workflow ANNOTATE_EGGNOG_CONTIGS {
    take:
        contigs
        diamond_db
        eggnog_db
    main:
        SEARCH_ORTHOLOGS_CONTIGS(contigs, diamond_db, "contigs")
        ANNOTATE_CONTIGS(SEARCH_ORTHOLOGS_CONTIGS.out.hits, eggnog_db, "contigs")

        collated_orthologs = COLLATE_HITS_CONTIGS(SEARCH_ORTHOLOGS_CONTIGS.out.hits | collect(flat: false), "${params.runId}_eggnog_orthologs_contigs", "types collate-orthologs", "--i-orthologs", "--o-collated-orthologs", true)
        collated_annotations = COLLATE_ANNOTATIONS_CONTIGS(ANNOTATE_CONTIGS.out.annotations | collect(flat: false), "${params.runId}_eggnog_annotations_contigs", "types collate-ortholog-annotations", "--i-ortholog-annotations", "--o-collated-annotations", true)

        if (params.functional_annotation.ortholog_search.fetchArtifact) {
            FETCH_ARTIFACT_ORTHOLOGS(collated_orthologs)
        }
        if (params.functional_annotation.annotation.fetchArtifact) {
            FETCH_ARTIFACT_ANNOTATIONS(collated_annotations)
        }
}
