import jinja2
import argparse
import re


def convert_time_to_slurm_format(time_str):
    """Convert Nextflow time format to Slurm HH:MM:SS format."""
    total_seconds = 0
    print(f"Parsing time: {time_str}")
    
    # Match groups of numbers followed by d, h, m, or s
    matches = re.findall(r'(\d+)([dhms])', time_str)
    for value, unit in matches:
        if unit == 'd':  # Days to seconds
            total_seconds += int(value) * 86400
        elif unit == 'h':  # Hours to seconds
            total_seconds += int(value) * 3600
        elif unit == 'm':  # Minutes to seconds
            total_seconds += int(value) * 60
        elif unit == 's':  # Seconds
            total_seconds += int(value)
    
    # Convert total seconds into HH:MM:SS format
    hours = total_seconds // 3600
    minutes = (total_seconds % 3600) // 60
    seconds = total_seconds % 60

    return f"{hours:02}:{minutes:02}:{seconds:02}"

def main(
    template_path,
    output_path,
    memory,
    cpus,
    total_time,
    nodes_per_block,
    max_blocks,
    worker_init,
):
    total_time_slurm = convert_time_to_slurm_format(total_time)

    # Load template from file
    with open(template_path) as f:
        template_content = f.read()

    # Values to populate the template
    values = {
        "memory": memory.replace(" ", ""),
        "cpus": cpus,
        "total_time": total_time_slurm,
        "nodes_per_block": nodes_per_block,
        "max_blocks": max_blocks,
        "worker_init": worker_init,
    }

    # Render the template
    template = jinja2.Template(template_content)
    with open(output_path, "w") as f:
        f.write(template.render(values))


if __name__ == "__main__":
    # Argument parser for command-line inputs
    parser = argparse.ArgumentParser(
        description="Generate a TOML file using Jinja2 template."
    )
    parser.add_argument(
        "-t", "--template-path", required=True, help="Path to the Jinja2 template file"
    )
    parser.add_argument(
        "-o", "--output-path", required=True, help="Path for the output TOML file"
    )
    parser.add_argument(
        "-m", "--memory", required=True, help="Memory value to include in the TOML file"
    )
    parser.add_argument(
        "-c", "--cpus", default="1", help="CPU value to include in the TOML file"
    )
    parser.add_argument(
        "-T",
        "--total-time",
        required=True,
        help="Total time value to include in the TOML file",
    )
    parser.add_argument(
        "-n", "--nodes-per-block", default="1", help="Nodes per block value"
    )
    parser.add_argument("-b", "--max-blocks", default="1", help="Max blocks value")
    parser.add_argument(
        "-w", "--worker-init", default="", help="Custom worker instructions"
    )

    args = parser.parse_args()
    main(
        template_path=args.template_path,
        output_path=args.output_path,
        memory=args.memory,
        cpus=args.cpus,
        total_time=args.total_time,
        nodes_per_block=args.nodes_per_block,
        max_blocks=args.max_blocks,
        worker_init=args.worker_init,
    )
