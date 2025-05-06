include { INDEX_CONTIGS } from '../modules/genome_assembly'
include { MAP_READS_TO_CONTIGS } from '../modules/genome_assembly'
include { ASSEMBLE_METASPADES } from '../modules/genome_assembly'
include { ASSEMBLE_MEGAHIT } from '../modules/genome_assembly'
include { EVALUATE_CONTIGS } from '../modules/genome_assembly'
include { EVALUATE_CONTIGS_NO_READS } from '../modules/genome_assembly'
include { FILTER_CONTIGS } from '../modules/genome_assembly'
include { COLLATE_PARTITIONS as COLLATE_READS } from '../modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_CONTIGS } from '../modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_MAPS } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_CONTIGS } from '../modules/data_prep'
include { CONTIG_ABUNDANCE } from '../subworkflows/abundance_estimation'

workflow ASSEMBLE {
    take:
        reads
        q2_cache

    main:
        if (params.genome_assembly.assembler.toLowerCase() == 'metaspades') {
            contigs = ASSEMBLE_METASPADES(reads, q2_cache)
        } else if (params.genome_assembly.assembler.toLowerCase() == 'megahit') {
            contigs = ASSEMBLE_MEGAHIT(reads)
        } else {
            error "Unknown assembler: ${params.genome_assembly.assembler}"
        }

        if (params.genome_assembly.filtering.enabled) {
            contigs = FILTER_CONTIGS(contigs)
        }

        contigs_all = contigs | collect(flat: false)
        contigs_all = COLLATE_CONTIGS(contigs_all, "${params.runId}_contigs", "assembly collate-contigs", "--i-contigs", "--o-collated-contigs", true)

        if (params.genome_assembly.fetchArtifact) {
            FETCH_ARTIFACT_CONTIGS(contigs_all)
        }

        if (params.assembly_qc.enabled || params.binning.enabled || params.abundance_estimation.enabledFor.contains("contigs")) {
            if (params.assembly_qc.useMappedReads || params.binning.enabled || params.abundance_estimation.enabledFor.contains("contigs")) {
                indexed_contigs = INDEX_CONTIGS(contigs)
                indexed_contigs_with_reads = indexed_contigs.combine(reads, by: 0)

                mapped_reads = MAP_READS_TO_CONTIGS(indexed_contigs_with_reads)
                mapped_reads_all = mapped_reads | collect(flat: false)
                maps_all = COLLATE_MAPS(mapped_reads_all, "${params.runId}_reads_to_contigs", "assembly collate-alignments", "--i-alignment-maps", "--o-collated-alignment-maps", true)
                if (params.assembly_qc.enabled && params.assembly_qc.useMappedReads) {
                    EVALUATE_CONTIGS(contigs_all, maps_all, q2_cache)
                } else if (params.assembly_qc.enabled) {
                    EVALUATE_CONTIGS_NO_READS(contigs_all, q2_cache)
                }
                if (params.abundance_estimation.enabledFor.contains("contigs")) {
                    CONTIG_ABUNDANCE(contigs_all, maps_all, q2_cache)
                }
            } else {
                mapped_reads = ""
                if (params.assembly_qc.enabled) {
                    EVALUATE_CONTIGS_NO_READS(contigs_all, q2_cache)
                }
            }
        } else {
            mapped_reads = ""
        }

    emit:
        contigs
        mapped_reads
}
