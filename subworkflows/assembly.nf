include { INDEX_CONTIGS } from '../modules/genome_assembly'
include { MAP_READS_TO_CONTIGS } from '../modules/genome_assembly'
include { ASSEMBLE_METASPADES } from '../modules/genome_assembly'
include { ASSEMBLE_MEGAHIT } from '../modules/genome_assembly'
include { EVALUATE_CONTIGS } from '../modules/genome_assembly'
include { FILTER_CONTIGS } from '../modules/genome_assembly'
include { COLLATE_PARTITIONS as COLLATE_READS } from '../modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_CONTIGS } from '../modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_MAPS } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_CONTIGS } from '../modules/data_prep'


workflow ASSEMBLE {
    take:
        reads
        q2_cache

    main:
        if (params.genome_assembly.assembler.toLowerCase() == 'metaspades') {
            contigs = ASSEMBLE_METASPADES(reads, q2_cache)
        } else if (params.genome_assembly.assembler.toLowerCase() == 'megahit') {
            contigs = ASSEMBLE_MEGAHIT(reads, q2_cache)
        } else {
            error "Unknown assembler: ${params.genome_assembly.assembler}"
        }

        if (params.genome_assembly.filtering.enabled) {
            contigs = FILTER_CONTIGS(contigs, q2_cache)
        }

        contigs_all = contigs | map { _id, key -> key } | collect
        contigs_all = COLLATE_CONTIGS(contigs_all, "${params.runId}_contigs", "assembly collate-contigs", "--i-contigs", "--o-collated-contigs", true)

        if (params.genome_assembly.fetchArtifact) {
            FETCH_ARTIFACT_CONTIGS(contigs_all)
        }

        if (params.assembly_qc.enabled || params.binning.enabled) {
            indexed_contigs = INDEX_CONTIGS(contigs, q2_cache)
            indexed_contigs_with_reads = indexed_contigs.combine(reads, by: 0)

            mapped_reads = MAP_READS_TO_CONTIGS(indexed_contigs_with_reads, q2_cache)
            maps_all = mapped_reads | map { _id, key -> key } | collect
            maps_all = COLLATE_MAPS(maps_all, "${params.runId}_reads_to_contigs", "assembly collate-alignments", "--i-alignments", "--o-collated-alignments", true)

            if (params.assembly_qc.enabled) {
                EVALUATE_CONTIGS(contigs_all, maps_all, q2_cache)
            }
        }

    emit:
        contigs
        mapped_reads
}
