include { ASSEMBLE_METASPADES } from '../modules/genome_assembly'
include { ASSEMBLE_MEGAHIT } from '../modules/genome_assembly'
include { EVALUATE_CONTIGS } from '../modules/genome_assembly'
include { COLLATE_PARTITIONS as COLLATE_READS } from '../modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_CONTIGS } from '../modules/data_prep'
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

        contigs_all = contigs | map { _id, key -> key } | collect
        contigs_all = COLLATE_CONTIGS(contigs_all, "contigs", "assembly collate-contigs", "--i-contigs", "--o-collated-contigs", true)

        if (params.genome_assembly.fetchArtifact) {
            FETCH_ARTIFACT_CONTIGS(contigs_all)
        }

        if (params.assembly_qc.enabled) {
            // reads_all = reads | map { _id, key -> key } | collect
            reads = reads | map { _id, key -> key }
            // TODO: reads also need to be collated!
            EVALUATE_CONTIGS(contigs_all, reads, q2_cache)
        }

    emit:
        contigs
}
