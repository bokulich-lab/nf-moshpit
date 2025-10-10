#!/usr/bin/env nextflow

// Function to parse YAML file, extract UUID, construct path, and get directory size in GB
def getDirectorySizeInGB(inputPath, basePath) {
    // Parse the YAML file to extract UUID from "data" key
    def yamlFile = new java.io.File(inputPath)
    def uuid = null
    
    if (yamlFile.exists()) {
        yamlFile.eachLine { line ->
            if (line.startsWith("data:")) {
                uuid = line.split(":", 2)[1].trim()
            }
        }
    }
    
    if (!uuid) {
        throw new Exception("Could not find 'data' key in YAML file: ${inputPath}")
    }
    
    // Construct the final path by appending UUID to base path
    def concatenatedPath = java.nio.file.Paths.get(basePath).resolve(uuid).toString()
    
    // Calculate directory size in GB
    def directory = new java.io.File(concatenatedPath)
    def sizeInBytes = 0L
    if (directory.exists() && directory.isDirectory()) {
        directory.eachFileRecurse { file ->
            if (file.isFile()) {
                sizeInBytes += file.length()
            }
        }
    }
    def sizeInGB = sizeInBytes / (1024.0 * 1024.0 * 1024.0)
    def sizeInGBRoundedUp = Math.ceil(1.1 * sizeInGB) as int
    
    println "Extracted UUID: ${uuid}"
    println "Constructed path: ${concatenatedPath}"
    println "Directory size: ${sizeInGB.round(1)} GB (rounded up: ${sizeInGBRoundedUp} GB)"
    
    return [
        uuid: uuid,
        concatenatedPath: concatenatedPath,
        sizeInGB: sizeInGB.round(2),
        sizeInGBRoundedUp: sizeInGBRoundedUp
    ]
}
