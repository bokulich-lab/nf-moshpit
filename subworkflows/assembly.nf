include { ASSEMBLE_METASPADES } from '../modules/genome_assembly'
include { ASSEMBLE_MEGAHIT } from '../modules/genome_assembly'
include { EVALUATE_CONTIGS } from '../modules/genome_assembly'

workflow ASSEMBLE {
    take:
        reads
        q2Cache
    main:
        if (params.genome_assembly.assembler.toLowerCase() == 'metaspades') {
            contigs = ASSEMBLE_METASPADES(reads, q2Cache)
        } else if (params.genome_assembly.assembler.toLowerCase() == 'megahit') {
            contigs = ASSEMBLE_MEGAHIT(reads, q2Cache)
        } else {
            error "Unknown assembler: ${params.genome_assembly.assembler}"
        }

        if (params.assembly_qc.enabled) {
            contig_qc = EVALUATE_CONTIGS(contigs, reads, q2Cache)
        }
        
    emit:
        contigs
}
