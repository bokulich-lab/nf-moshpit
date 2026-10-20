#!/usr/bin/env python
"""Build a contig map and unbinned artifact for one Nextflow sample partition."""
import argparse
from pathlib import Path


def summarize(cache_dir, contigs_key, bins_key, map_key, unbinned_key):
    import skbio
    from qiime2 import Artifact, Cache
    from qiime2.plugins import assembly
    from q2_types.per_sample_sequences import MultiFASTADirectoryFormat

    cache = Cache(cache_dir)
    contigs = cache.load(contigs_key)
    bins = cache.load(bins_key).view(MultiFASTADirectoryFormat)
    samples = bins.sample_dict()
    if len(samples) != 1:
        raise ValueError("Expected exactly one sample in a binning partition")
    contig_map = {}
    for mag_id, fasta in next(iter(samples.values())).items():
        contig_map[mag_id] = [
            seq.metadata["id"] for seq in skbio.read(str(fasta), format="fasta")
        ]
    if not contig_map:
        raise ValueError("No MAGs were formed during binning")
    binned_ids = sorted({cid for ids in contig_map.values() for cid in ids})
    # Each call contains one sample, so reused IDs in other samples cannot remove
    # its unbinned sequences. Keep empty FASTAs when every contig was binned.
    unbinned, = assembly.actions.filter_contigs(
        contigs, on="contig", ids=binned_ids, exclude_ids=True, remove_empty=False
    )
    cache.save(Artifact.import_data("FeatureMap[MAGtoContigs]", contig_map), map_key)
    cache.save(unbinned, unbinned_key)
    Path(map_key).touch()
    Path(unbinned_key).touch()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("cache_dir", "contigs_key", "bins_key", "map_key", "unbinned_key"):
        parser.add_argument(name)
    summarize(**vars(parser.parse_args()))
