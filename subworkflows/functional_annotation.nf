include { SEARCH_ORTHOLOGS_EGGNOG as SEARCH_ORTHOLOGS_MAGS_DEREP; SEARCH_ORTHOLOGS_EGGNOG as SEARCH_ORTHOLOGS_CONTIGS; SEARCH_ORTHOLOGS_EGGNOG as SEARCH_ORTHOLOGS_MAGS } from '../modules/functional_annotation'
include { ANNOTATE_EGGNOG as ANNOTATE_MAGS_DEREP; ANNOTATE_EGGNOG as ANNOTATE_CONTIGS; ANNOTATE_EGGNOG as ANNOTATE_MAGS } from '../modules/functional_annotation'
include { COLLATE_PARTITIONS as COLLATE_ANNOTATIONS_CONTIGS; COLLATE_PARTITIONS as COLLATE_ANNOTATIONS_MAGS; COLLATE_PARTITIONS_DEREP as COLLATE_ANNOTATIONS_MAGS_DEREP} from '../modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_HITS_CONTIGS; COLLATE_PARTITIONS as COLLATE_HITS_MAGS; COLLATE_PARTITIONS_DEREP as COLLATE_HITS_MAGS_DEREP } from '../modules/data_prep'
include { EXTRACT_ANNOTATIONS; MULTIPLY_TABLES; DRAW_ANNOTATION_BARPLOT; TRANSFER_ANNOTATIONS; ESTIMATE_TFA } from '../modules/functional_annotation'
include { FETCH_ARTIFACT as FETCH_TFA_TABLE; FETCH_ARTIFACT as FETCH_TFA_TAXONOMY; FETCH_ARTIFACT as FETCH_MULTIPLIED_TABLE } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_ORTHOLOGS } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_ANNOTATIONS } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_EXTRACTED_ANNOTATIONS } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_EXTRACTED_ANNOTATION_MAP } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_EXTRACTED_ANNOTATIONS_PER_CONTIG } from '../modules/data_prep'
include { CLEAN_UP_CACHES } from '../modules/data_prep'
include { FIX_CACHE_PERMISSIONS } from '../modules/data_prep'

workflow ANNOTATE_EGGNOG_MAGS {
    take:
        mags
        diamond_db
        eggnog_db
    main:
        SEARCH_ORTHOLOGS_MAGS(mags, diamond_db, "mags")
        ANNOTATE_MAGS(SEARCH_ORTHOLOGS_MAGS.out.hits, eggnog_db, "mags")

        if (params.binning.qc.busco.enabled) {
            orthologs_key = "${params.runId}_eggnog_orthologs_mags_${params.binning.primary}_${params.binning.qc.busco.selectLineage}"
            annotations_key = "${params.runId}_eggnog_annotations_mags_${params.binning.primary}_${params.binning.qc.busco.selectLineage}"
        } else {
            orthologs_key = "${params.runId}_eggnog_orthologs_mags_${params.binning.primary}"
            annotations_key = "${params.runId}_eggnog_annotations_mags_${params.binning.primary}"
        }

        collated_orthologs = COLLATE_HITS_MAGS(SEARCH_ORTHOLOGS_MAGS.out.hits | collect(flat: false), orthologs_key, "types collate-orthologs", "--i-orthologs", "--o-collated-orthologs", true)
        collated_annotations = COLLATE_ANNOTATIONS_MAGS(ANNOTATE_MAGS.out.annotations | collect(flat: false), annotations_key, "types collate-ortholog-annotations", "--i-ortholog-annotations", "--o-collated-annotations", true)

        if (params.functional_annotation.ortholog_search.fetchArtifact) {
            FETCH_ARTIFACT_ORTHOLOGS(collated_orthologs)
        }
        if (params.functional_annotation.annotation.fetchArtifact) {
            FETCH_ARTIFACT_ANNOTATIONS(collated_annotations)
        }
    emit:
        collated_orthologs
        annotations = collated_annotations
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
            def batchId = filename.substring("${params.runId}_mags_${params.binning.primary}_derep_partitioned_".length())
            tuple("batch_${batchId}", partition)
        }
        SEARCH_ORTHOLOGS_MAGS_DEREP(mags_derep, diamond_db, "mags_derep")
        ANNOTATE_MAGS_DEREP(SEARCH_ORTHOLOGS_MAGS_DEREP.out.hits, eggnog_db, "mags_derep")

        if (params.binning.qc.busco.enabled) {
            orthologs_key = "${params.runId}_eggnog_orthologs_mags_${params.binning.primary}_derep_${params.binning.qc.busco.selectLineage}"
            annotations_key = "${params.runId}_eggnog_annotations_mags_${params.binning.primary}_derep_${params.binning.qc.busco.selectLineage}"
        } else {
            orthologs_key = "${params.runId}_eggnog_orthologs_mags_${params.binning.primary}_derep"
            annotations_key = "${params.runId}_eggnog_annotations_mags_${params.binning.primary}_derep"
        }
        collated_orthologs = COLLATE_HITS_MAGS_DEREP(SEARCH_ORTHOLOGS_MAGS_DEREP.out.hits | collect(flat: false), orthologs_key, "types collate-orthologs", "--i-orthologs", "--o-collated-orthologs", true)
        collated_annotations = COLLATE_ANNOTATIONS_MAGS_DEREP(ANNOTATE_MAGS_DEREP.out.annotations | collect(flat: false), annotations_key, "types collate-ortholog-annotations", "--i-ortholog-annotations", "--o-collated-annotations", true)


        if (params.functional_annotation.cleanUp) {
            wait_for_collation = collated_orthologs.mix(collated_annotations).collect().map { true }
            CLEAN_UP_CACHES(wait_for_collation, "${params.q2TemporaryCachesDir}/mags")
        } else {
             // If not cleaning up, fix permissions on each batch's cache
             // We can recreate the batch IDs from params.functional_annotation.partitionBatchCount.
             
             batch_ids = Channel.of(0..(params.functional_annotation.partitionBatchCount - 1))
             mags_cache_batches = batch_ids.map { batch_id -> 
                tuple("mags_batch_${batch_id}", "${params.q2TemporaryCachesDir}/mags/batch_${batch_id}", collated_annotations) 
             }
             FIX_CACHE_PERMISSIONS(mags_cache_batches)
        }

        if (params.functional_annotation.annotation.extract != "") {
            annotation_type = Channel.of(params.functional_annotation.annotation.extract.types.split(","))
            EXTRACT_ANNOTATIONS(collated_annotations.first(), annotation_type, "mags_derep", q2_cache.first())
            if (params.functional_annotation.annotation.extract.fetchArtifact) {
                FETCH_ARTIFACT_EXTRACTED_ANNOTATIONS(EXTRACT_ANNOTATIONS.out.counts_per_genome | map { _type, key -> key })
                FETCH_ARTIFACT_EXTRACTED_ANNOTATION_MAP(EXTRACT_ANNOTATIONS.out.annotation_map | map { _type, key -> key })
                FETCH_ARTIFACT_EXTRACTED_ANNOTATIONS_PER_CONTIG(EXTRACT_ANNOTATIONS.out.counts_per_contig | map { _type, key -> key })
            }
        }

        if (params.functional_annotation.ortholog_search.fetchArtifact) {
            FETCH_ARTIFACT_ORTHOLOGS(collated_orthologs)
        }
        if (params.functional_annotation.annotation.fetchArtifact) {
            FETCH_ARTIFACT_ANNOTATIONS(collated_annotations)
        }
    emit:
        extracted_annotations = EXTRACT_ANNOTATIONS.out.counts_per_genome
        annotation_map = EXTRACT_ANNOTATIONS.out.annotation_map
        counts_per_contig = EXTRACT_ANNOTATIONS.out.counts_per_contig
}

workflow COMBINE_ANNOTATION_ABUNDANCE {
    take:
        abundance_table
        annotation_counts
        input_type
        q2_cache
    main:
        qzv_outputs = Channel.empty()
        multiplied = MULTIPLY_TABLES(abundance_table.first(), annotation_counts, input_type, q2_cache.first())
        DRAW_ANNOTATION_BARPLOT(multiplied, input_type)
        qzv_outputs = qzv_outputs.mix(DRAW_ANNOTATION_BARPLOT.out.qzv)
        if (params.functional_annotation.annotation.extract.fetchArtifact) {
            FETCH_MULTIPLIED_TABLE(multiplied | map { _type, key -> key })
        }
    emit:
        feature_table = multiplied
        qzv = qzv_outputs
}

workflow ANNOTATE_EGGNOG_CONTIGS {
    take:
        contigs
        diamond_db
        eggnog_db
        q2_cache
    main:
        SEARCH_ORTHOLOGS_CONTIGS(contigs, diamond_db, "contigs")
        ANNOTATE_CONTIGS(SEARCH_ORTHOLOGS_CONTIGS.out.hits, eggnog_db, "contigs")

        collated_orthologs = COLLATE_HITS_CONTIGS(SEARCH_ORTHOLOGS_CONTIGS.out.hits | collect(flat: false), "${params.runId}_eggnog_orthologs_contigs", "types collate-orthologs", "--i-orthologs", "--o-collated-orthologs", true)
        collated_annotations = COLLATE_ANNOTATIONS_CONTIGS(ANNOTATE_CONTIGS.out.annotations | collect(flat: false), "${params.runId}_eggnog_annotations_contigs", "types collate-ortholog-annotations", "--i-ortholog-annotations", "--o-collated-annotations", true)

        if (params.functional_annotation.annotation.extract != "") {
            annotation_type = Channel.of(params.functional_annotation.annotation.extract.types.split(","))
            EXTRACT_ANNOTATIONS(collated_annotations.first(), annotation_type, "contigs", q2_cache.first())
            if (params.functional_annotation.annotation.extract.fetchArtifact) {
                FETCH_ARTIFACT_EXTRACTED_ANNOTATIONS(EXTRACT_ANNOTATIONS.out.counts_per_genome | map { _type, key -> key })
                FETCH_ARTIFACT_EXTRACTED_ANNOTATION_MAP(EXTRACT_ANNOTATIONS.out.annotation_map | map { _type, key -> key })
                FETCH_ARTIFACT_EXTRACTED_ANNOTATIONS_PER_CONTIG(EXTRACT_ANNOTATIONS.out.counts_per_contig | map { _type, key -> key })
            }
        }

        if (params.functional_annotation.ortholog_search.fetchArtifact) {
            FETCH_ARTIFACT_ORTHOLOGS(collated_orthologs)
        }
        if (params.functional_annotation.annotation.fetchArtifact) {
            FETCH_ARTIFACT_ANNOTATIONS(collated_annotations)
        }
    emit:
        collated_orthologs
        annotations = collated_annotations
        counts_per_contig = EXTRACT_ANNOTATIONS.out.counts_per_contig
        annotation_map = EXTRACT_ANNOTATIONS.out.annotation_map
}

workflow TRANSFER_MAG_ANNOTATIONS {
    take:
        source_annotations
        destination_sequences
        input_type
        q2_cache
    main:
        annotations = TRANSFER_ANNOTATIONS(source_annotations.first(), destination_sequences.first(), input_type)
        annotation_types = Channel.of(params.functional_annotation.annotation.extract.types.split(','))
        extracted = EXTRACT_ANNOTATIONS(annotations.first(), annotation_types, input_type, q2_cache.first())
        if (params.functional_annotation.annotation.fetchArtifact) {
            FETCH_ARTIFACT_ANNOTATIONS(annotations)
        }
        if (params.functional_annotation.annotation.extract.fetchArtifact) {
            FETCH_ARTIFACT_EXTRACTED_ANNOTATIONS(extracted.counts_per_genome.map { type, key -> key })
            FETCH_ARTIFACT_EXTRACTED_ANNOTATION_MAP(extracted.annotation_map.map { type, key -> key })
            FETCH_ARTIFACT_EXTRACTED_ANNOTATIONS_PER_CONTIG(extracted.counts_per_contig.map { type, key -> key })
        }
    emit:
        annotations = annotations
        extracted_annotations = extracted.counts_per_genome
        completion = annotations.mix(extracted.counts_per_genome).mix(extracted.annotation_map).mix(extracted.counts_per_contig)
}

workflow CONTIG_TFA {
    take:
        abundance
        inventory
        taxonomy
        taxon_map
    main:
        metadata = params.metadata ? Channel.value(file(params.metadata, checkIfExists: true)) : Channel.value([])
        results = ESTIMATE_TFA(abundance.first(), inventory, taxonomy.first(), taxon_map.first(), metadata)
        if (params.functional_annotation.tfa.fetchArtifact) {
            FETCH_TFA_TABLE(results.tfa.map { type, key -> key })
            FETCH_TFA_TAXONOMY(results.gene_taxonomy.map { type, key -> key })
        }
    emit:
        tfa = results.tfa
        gene_taxonomy = results.gene_taxonomy
        qzv = results.qzv
}
