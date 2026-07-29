#!/usr/bin/env nextflow

// Parameter validation script

def paramIsSet(value) {
    value != null && value.toString().trim() != '' && value.toString().toLowerCase() != 'null'
}

def effectiveContainer(paramValue) {
    paramIsSet(paramValue) ? paramValue : null
}

def binnerEnabled(binnerConfig) {
    binnerConfig != null && binnerConfig.enabled == true
}

def getEnabledBinners() {
    def enabled = []
    if (binnerEnabled(params.binning.metabat2)) enabled << 'metabat2'
    if (binnerEnabled(params.binning.semibin2)) enabled << 'semibin2'
    return enabled
}

def validateBinningParams() {
    def errors = []
    if (!params.binning.enabled) {
        return errors
    }

    def validBinners = ['metabat2', 'semibin2']
    def enabledBinners = getEnabledBinners()

    if (enabledBinners.isEmpty()) {
        errors.add("ERROR: Binning is enabled but no binner is enabled (set binning.metabat2.enabled and/or binning.semibin2.enabled)")
    }

    def primary = params.binning.primary?.toString()?.trim()
    if (!primary || !(primary in validBinners)) {
        errors.add("ERROR: binning.primary must be one of: ${validBinners.join(', ')}")
    } else if (!enabledBinners.isEmpty() && !(primary in enabledBinners)) {
        errors.add("ERROR: binning.primary '${primary}' must be one of the enabled binners (${enabledBinners.join(', ')})")
    }

    if (params.binning.qc.filtering.enabled && !params.binning.qc.busco.enabled) {
        errors.add("ERROR: MAG filtering is enabled but BUSCO QC is disabled")
    }

    if (binnerEnabled(params.binning.metabat2)) {
        def metabat = params.binning.metabat2
        if (metabat.min_contig != null && metabat.min_contig.toString().toLowerCase() != 'null') {
            def minContig = metabat.min_contig as int
            if (minContig < 1500) {
                errors.add("ERROR: binning.metabat2.min_contig must be at least 1500 (got ${minContig})")
            }
        }
        if (metabat.seed != null && (metabat.seed as int) < 0) {
            errors.add("ERROR: binning.metabat2.seed must be >= 0")
        }
    }

    if (binnerEnabled(params.binning.semibin2)) {
        def semibin = params.binning.semibin2
        def validTrainingTypes = ['semi', 'self']
        if (!semibin.training_type || !(semibin.training_type.toString() in validTrainingTypes)) {
            errors.add("ERROR: binning.semibin2.training_type must be one of: ${validTrainingTypes.join(', ')}")
        }
        ['min_len', 'epochs', 'batch_size'].each { paramName ->
            def value = semibin[paramName]
            if (value == null || (value as int) < 1) {
                errors.add("ERROR: binning.semibin2.${paramName} must be a positive integer")
            }
        }
        if (semibin.random_seed != null && (semibin.random_seed as int) < 0) {
            errors.add("ERROR: binning.semibin2.random_seed must be >= 0")
        }
    }

    return errors
}

// Function to validate mandatory parameters
def validateMandatoryParams() {
    def errors = []
    
    // Core mandatory parameters
    if (!params.runId) errors.add("ERROR: runId parameter is required")
    if (!params.outputDir) errors.add("ERROR: outputDir parameter is required")
    
    // Either a default/annotate container or condaEnv must be specified
    def annotateContainer = effectiveContainer(params.containerAnnotate) ?: effectiveContainer(params.container)
    if (!annotateContainer && !paramIsSet(params.condaEnv)) {
        errors.add("ERROR: Either container, containerAnnotate, or condaEnv must be specified")
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
    
    // Taxonomic classification database validation (Kraken2/Bracken)
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
    
    // Kaiju database validation
    if (params.taxonomic_classification.kaiju.enabledFor) {
        if (!params.databases.kaiju.cache || !params.databases.kaiju.key || !params.databases.kaiju.databaseType) {
            errors.add("ERROR: Kaiju classification is enabled but Kaiju database cache, key, and databaseType must all be specified")
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
        
        if (!paramIsSet(params.containerCheckM) && !paramIsSet(params.container)) {
            errors.add("ERROR: CheckM is enabled but no CheckM container is specified (set containerCheckM or container)")
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

    // HUMAnN 3 database validation
    if (params.humann3.enabled) {
        if (!params.databases.humann3Chocophlan.cache && !params.databases.humann3Chocophlan.key) {
            errors.add("ERROR: HUMAnN 3 is enabled but no ChocoPhlAn database cache or key is specified")
        }
        if (!params.databases.humann3TranslatedSearch.cache && !params.databases.humann3TranslatedSearch.key) {
            errors.add("ERROR: HUMAnN 3 is enabled but no translated-search database cache or key is specified")
        }
        if (!params.databases.humann3Metaphlan.cache && !params.databases.humann3Metaphlan.key) {
            errors.add("ERROR: HUMAnN 3 is enabled but no MetaPhlAn database cache or key is specified")
        }
        if (!paramIsSet(params.containerHumann3) && !paramIsSet(params.container)) {
            errors.add("ERROR: HUMAnN 3 is enabled but no HUMAnN 3 container is specified (set containerHumann3 or container)")
        }
    }
    
    return errors
}

// Validate module-specific parameters
def validateModuleParams() {
    def errors = []

    errors.addAll(validateBinningParams())
    
    // Validate genome assembly parameters
    if (params.genome_assembly.enabled) {
        def assembler = params.genome_assembly.assembler.toLowerCase()
        if (assembler != "megahit" && assembler != "metaspades") {
            errors.add("ERROR: assembler must be either 'megahit' or 'metaspades', got '${assembler}'")
        }
    }

    def abundanceTargets = params.abundance_estimation.enabledFor?.split(',')*.trim() ?: []
    def usesAssemblyContainer = params.genome_assembly.enabled ||
        params.binning.enabled ||
        paramIsSet(params.read_simulation.samples) ||
        abundanceTargets.any { it in ['contigs', 'derep'] }
    if (!paramIsSet(params.condaEnv) && usesAssemblyContainer) {
        def assemblyContainer = effectiveContainer(params.containerAssembly) ?: effectiveContainer(params.container)
        if (!assemblyContainer) {
            errors.add("ERROR: Assembly plugin processes are required but no assembly container is specified (set containerAssembly or container)")
        }
    }

    def usesMagContainer = params.binning.enabled ||
        params.dereplication.enabled ||
        abundanceTargets.any { it in ['contigs', 'derep'] } ||
        params.functional_annotation.enabledFor?.contains('derep')
    if (!paramIsSet(params.condaEnv) && usesMagContainer) {
        def magContainer = effectiveContainer(params.containerMag) ?:
            effectiveContainer(params.containerAnnotate) ?:
            effectiveContainer(params.container)
        if (!magContainer) {
            errors.add("ERROR: MAG plugin processes are required but no MAG container is specified (set containerMag, containerAnnotate, or container)")
        }
    }
    
    // Validate classification parameters (Kraken2/Bracken)
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
    
    // Validate Kaiju classification parameters
    if (params.taxonomic_classification.kaiju.enabledFor) {
        def validTargets = ["reads", "contigs"]
        def targets = params.taxonomic_classification.kaiju.enabledFor.split(",").collect { it.trim() }
        def invalidTargets = targets.findAll { !(it in validTargets) }
        
        if (invalidTargets) {
            errors.add("ERROR: Invalid targets for taxonomic_classification.kaiju.enabledFor: ${invalidTargets.join(", ")}. Valid options are: ${validTargets.join(", ")}")
        }
        
        if (targets.contains("contigs") && !params.genome_assembly.enabled) {
            errors.add("ERROR: Kaiju classification for contigs is enabled, but genome assembly is disabled")
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

    if (params.dereplication.enabled && params.dereplication.method?.toString()?.toLowerCase() == 'skani') {
        if (!paramIsSet(params.containerSkani) && !paramIsSet(params.container)) {
            errors.add("ERROR: Skani dereplication is enabled but no Skani container is specified (set containerSkani or container)")
        }
    }

    if (params.dereplication.enabled && params.dereplication.method?.toString()?.toLowerCase() == 'sourmash') {
        if (!paramIsSet(params.containerSourmash) && !paramIsSet(params.container)) {
            errors.add("ERROR: Sourmash dereplication is enabled but no Sourmash container is specified (set containerSourmash or container)")
        }
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