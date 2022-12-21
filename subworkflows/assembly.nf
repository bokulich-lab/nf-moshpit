include { ASSEMBLE_METASPADES } from '../modules/genome_assembly'
include { ASSEMBLE_MEGAHIT } from '../modules/genome_assembly'
include { EVALUATE_CONTIGS } from '../modules/genome_assembly'

workflow ASSEMBLE {
    take:
        reads
    main:
        if (params.assembler.toLowerCase() == 'metaspades') {
            contigs = ASSEMBLE_METASPADES(reads)
        } else if (params.assembler.toLowerCase() == 'megahit') {
            contigs = ASSEMBLE_MEGAHIT(reads)
        } else {
            error "Unknown assembler: ${params.assembler}"
        }
        contig_qc = EVALUATE_CONTIGS(contigs, reads)
    emit:
        contigs
}

// workflow ASSEMBLE_MEGAHIT {
//     take:
//         reads
//     main:
//         contigs = ASSEMBLE_MEGAHIT(reads)
//         contig_qc = EVALUATE_CONTIGS(contigs, reads)
//     emit:
//         contigs
// }