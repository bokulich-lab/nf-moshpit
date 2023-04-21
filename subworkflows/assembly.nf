include { ASSEMBLE_METASPADES } from '../modules/genome_assembly'
include { ASSEMBLE_MEGAHIT } from '../modules/genome_assembly'
include { EVALUATE_CONTIGS } from '../modules/genome_assembly'

workflow ASSEMBLE {
    take:
        reads
    main:
        if (params.genome_assembly.assembler.toLowerCase() == 'metaspades') {
            contigs = ASSEMBLE_METASPADES(reads)
        } else if (params.genome_assembly.assembler.toLowerCase() == 'megahit') {
            contigs = ASSEMBLE_MEGAHIT(reads)
        } else {
            error "Unknown assembler: ${params.genome_assembly.assembler}"
        }

        if (params.assembly_qc.enabled) {
            contig_qc = EVALUATE_CONTIGS(contigs, reads)
        }
        
    emit:
        contigs
}
