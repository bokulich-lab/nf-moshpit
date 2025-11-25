#!/usr/bin/env nextflow

// Parameter validation script

// Function to validate mandatory parameters
def validateMandatoryParams() {
    def errors = []
    
    // Core mandatory parameters
    if (!params.runId) errors.add("ERROR: runId parameter is required")
    if (!params.outputDir) errors.add("ERROR: outputDir parameter is required")
    
    // Either container or condaEnv must be specified
    if (!params.container && !params.condaEnv) {
        errors.add("ERROR: Either container or condaEnv must be specified")
    }
    
    // Check for email only if using fondue to fetch data
    if (params.fondueAccessionIds && !params.email) {
        errors.add("ERROR: email parameter is required when using q2-fondue to fetch data")
    }

    // Add debug logging for input parameters
    // log.info "DEBUG: Input parameters check:"
    // log.info "  - inputReadsManifest: ${params.inputReadsManifest}"
    // log.info "  - inputReads: ${params.inputReads}"
    // log.info "  - inputReadsCache: ${params.inputReadsCache}"
    // log.info "  - metadata: ${params.metadata}"
    // log.info "  - fondueAccessionIds: ${params.fondueAccessionIds}"
    // log.info "  - read_simulation.sampleGenomes: ${params.read_simulation.sampleGenomes}"
    // log.info "  - read_simulation.taxon: ${params.read_simulation.taxon}"
    // log.info "  - read_simulation.nGenomes: ${params.read_simulation.nGenomes}"
    
    // Check if at least one valid input method is specified
    boolean hasManifestInput = params.inputReadsManifest != null && 
                              params.inputReadsManifest.toString().trim() != '' && 
                              params.inputReadsManifest.toString().toLowerCase() != 'null'
    
    boolean hasExistingReadsInput = params.inputReads != null && 
                                   params.inputReads.toString().trim() != '' && 
                                   params.inputReads.toString().toLowerCase() != 'null' &&
                                   params.inputReadsCache != null && 
                                   params.inputReadsCache.toString().trim() != '' && 
                                   params.inputReadsCache.toString().toLowerCase() != 'null' &&
                                   params.metadata != null && 
                                   params.metadata.toString().trim() != '' && 
                                   params.metadata.toString().toLowerCase() != 'null'
    
    boolean hasFondueInput = params.fondueAccessionIds != null && 
                            params.fondueAccessionIds.toString().trim() != '' && 
                            params.fondueAccessionIds.toString().toLowerCase() != 'null'
    
    boolean hasSimulationInput = (params.read_simulation.samples != null)
    
    // Log the validation results
    log.info "DEBUG: Input validation results:"
    log.info "  - Has manifest input: ${hasManifestInput}"
    log.info "  - Has existing reads input: ${hasExistingReadsInput}"
    log.info "  - Has fondue input: ${hasFondueInput}"
    log.info "  - Has simulation input: ${hasSimulationInput}"
    
    def inputMethodsProvided = [
        hasManifestInput,
        hasExistingReadsInput,
        hasFondueInput,
        hasSimulationInput
    ].count { it }
    
    if (inputMethodsProvided == 0) {
        errors.add("ERROR: No valid input method specified. Please provide one of: inputReadsManifest, (inputReads + inputReadsCache + metadata), fondueAccessionIds, or read_simulation parameters")
    } else if (inputMethodsProvided > 1) {
        errors.add("WARNING: Multiple input methods specified. The workflow will prioritize them in this order: inputReadsManifest, (inputReads+inputReadsCache+metadata), fondueAccessionIds, read_simulation")
    }
    
    // Validate specific parameters for each method
    if (hasManifestInput && !file(params.inputReadsManifest).exists()) {
        errors.add("ERROR: inputReadsManifest file does not exist: ${params.inputReadsManifest}")
    }
    
    if (hasExistingReadsInput && !file(params.metadata).exists()) {
        errors.add("ERROR: metadata file does not exist: ${params.metadata}")
    }
    
    if (hasFondueInput && !file(params.fondueAccessionIds).exists()) {
        errors.add("ERROR: fondueAccessionIds file does not exist: ${params.fondueAccessionIds}")
    }
    
    if (params.read_simulation.samples != null && 
        params.read_simulation.samples.toString().toLowerCase() != 'null' && 
        !file(params.read_simulation.samples).exists()) {
        errors.add("ERROR: samples file does not exist: ${params.read_simulation.samples}")
    }
    0
    return errors
}

// Validate database-related parameters
def validateDatabaseParams() {
    def errors = []
    
    // Host removal database validation
    if (params.host_removal.enabled) {
        if (!params.databases.hostRemoval.cache && !params.databases.hostRemoval.key) {
            errors.add("ERROR: Host removal is enabled but no database cache or key is specified")
        }
    }
    
    // Taxonomic classification database validation
    if (params.taxonomic_classification.enabledFor) {
        if (!params.databases.kraken2.cache && !params.databases.kraken2.key && !params.databases.kraken2.fetchCollection) {
            errors.add("ERROR: Taxonomic classification is enabled but no Kraken2 database cache, key, or fetchCollection is specified")
        }
        
        if (params.taxonomic_classification.bracken.enabled) {
            if (!params.databases.bracken.cache && !params.databases.bracken.key) {
                errors.add("ERROR: Bracken is enabled but no database cache or key is specified")
            }
        }
    }
    
    // BUSCO database validation
    if (params.binning.enabled && params.binning.qc.busco.enabled) {
        if (!params.databases.busco.cache && !params.databases.busco.key && !params.databases.busco.fetchLineages) {
            errors.add("ERROR: BUSCO is enabled but no database cache, key, or fetchLineages is specified")
        }
    }
    
    // CheckM database validation
    if (params.binning.enabled && params.binning.qc.checkm.enabled) {
        if (!params.databases.checkm.path || params.databases.checkm.path.toString().trim() == '' || params.databases.checkm.path.toString().toLowerCase() == 'null') {
            errors.add("ERROR: CheckM is enabled but no database path is specified")
        }
        
        if (!params.containerCheckM || params.containerCheckM.toString().trim() == '' || params.containerCheckM.toString().toLowerCase() == 'null') {
            errors.add("ERROR: CheckM is enabled but no CheckM container is specified")
        }
    }
    
    // Functional annotation database validation
    if (params.functional_annotation.enabledFor) {
        if (!params.databases.eggnogOrthologs.cache && !params.databases.eggnogOrthologs.key) {
            errors.add("ERROR: Functional annotation is enabled but no eggNOG orthologs database cache or key is specified")
        }
        
        if (!params.databases.eggnogAnnotations.cache && !params.databases.eggnogAnnotations.key) {
            errors.add("ERROR: Functional annotation is enabled but no eggNOG annotations database cache or key is specified")
        }
    }
    
    return errors
}

// Validate module-specific parameters
def validateModuleParams() {
    def errors = []
    
    // Validate genome assembly parameters
    if (params.genome_assembly.enabled) {
        def assembler = params.genome_assembly.assembler.toLowerCase()
        if (assembler != "megahit" && assembler != "metaspades") {
            errors.add("ERROR: assembler must be either 'megahit' or 'metaspades', got '${assembler}'")
        }
    }
    
    // Validate classification parameters
    if (params.taxonomic_classification.enabledFor) {
        def validTargets = ["reads", "contigs", "mags", "derep"]
        def targets = params.taxonomic_classification.enabledFor.split(",").collect { it.trim() }
        def invalidTargets = targets.findAll { !(it in validTargets) }
        
        if (invalidTargets) {
            errors.add("ERROR: Invalid targets for taxonomic_classification.enabledFor: ${invalidTargets.join(", ")}. Valid options are: ${validTargets.join(", ")}")
        }
        
        // If "mags" or "derep" is enabled, ensure binning is also enabled
        if ((targets.contains("mags") || targets.contains("derep")) && !params.binning.enabled) {
            errors.add("ERROR: Taxonomic classification for MAGs or dereplicated MAGs is enabled, but binning is disabled")
        }
        
        // If "derep" is enabled, ensure dereplication is also enabled
        if (targets.contains("derep") && !params.dereplication.enabled) {
            errors.add("ERROR: Taxonomic classification for dereplicated MAGs is enabled, but dereplication is disabled")
        }
    }
    
    // Validate functional annotation parameters
    if (params.functional_annotation.enabledFor) {
        def validTargets = ["contigs", "mags", "derep"]
        def targets = params.functional_annotation.enabledFor.split(",").collect { it.trim() }
        def invalidTargets = targets.findAll { !(it in validTargets) }
        
        if (invalidTargets) {
            errors.add("ERROR: Invalid targets for functional_annotation.enabledFor: ${invalidTargets.join(", ")}. Valid options are: ${validTargets.join(", ")}")
        }
        
        // If "mags" or "derep" is enabled, ensure binning is also enabled
        if ((targets.contains("mags") || targets.contains("derep")) && !params.binning.enabled) {
            errors.add("ERROR: Functional annotation for MAGs or dereplicated MAGs is enabled, but binning is disabled")
        }
        
        // If "derep" is enabled, ensure dereplication is also enabled
        if (targets.contains("derep") && !params.dereplication.enabled) {
            errors.add("ERROR: Functional annotation for dereplicated MAGs is enabled, but dereplication is disabled")
        }
    }
    
    // Validate abundance estimation parameters
    if (params.abundance_estimation.enabledFor) {
        def validTargets = ["contigs", "derep"]
        def targets = params.abundance_estimation.enabledFor.split(",").collect { it.trim() }
        def invalidTargets = targets.findAll { !(it in validTargets) }
        
        if (invalidTargets) {
            errors.add("ERROR: Invalid targets for abundance_estimation.enabledFor: ${invalidTargets.join(", ")}. Valid options are: ${validTargets.join(", ")}")
        }
        
        // If "derep" is enabled, ensure dereplication is also enabled
        if (targets.contains("derep") && !params.dereplication.enabled) {
            errors.add("ERROR: Abundance estimation for dereplicated MAGs is enabled, but dereplication is disabled")
        }
    }
    
    return errors
}

// Validate interdependent parameters
def validateWorkflowDependencies() {
    def errors = []
    
    // Dependency: If binning is enabled, assembly must be enabled
    if (params.binning.enabled && !params.genome_assembly.enabled) {
        errors.add("ERROR: Binning is enabled, but genome assembly is disabled")
    }
    
    // Dependency: If dereplication is enabled, binning must be enabled
    if (params.dereplication.enabled && !params.binning.enabled) {
        errors.add("ERROR: Dereplication is enabled, but binning is disabled")
    }
    
    return errors
}

// Main validation function
def validateParameters() {
    // Collect all validation errors
    def allErrors = []
    allErrors.addAll(validateMandatoryParams())
    allErrors.addAll(validateDatabaseParams())
    allErrors.addAll(validateModuleParams())
    allErrors.addAll(validateWorkflowDependencies())
    
    // Print warnings and errors
    def warnings = allErrors.findAll { it.startsWith("WARNING:") }
    def errors = allErrors.findAll { it.startsWith("ERROR:") }
    
    if (warnings) {
        log.warn "=== PARAMETER WARNINGS ==="
        warnings.each { log.warn it.replace("WARNING: ", "") }
    }
    
    if (errors) {
        log.error "=== PARAMETER VALIDATION ERRORS ==="
        errors.each { log.error it.replace("ERROR: ", "") }
        exit 1
    }
    
    // Log validation success if no errors
    if (!errors) {
        log.info "Parameter validation successful"
    }
    
    return !errors
}

// Export the validation function
return this 