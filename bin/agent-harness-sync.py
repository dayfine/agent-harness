#!/usr/bin/env python3
import os
import sys
import subprocess
import tempfile
import difflib

def run_cmd(cmd, cwd=None):
    subprocess.check_call(cmd, shell=True, cwd=cwd)

def extract_frontmatter(content):
    lines = content.splitlines()
    if not lines or lines[0].strip() != '---':
        return "", content
    
    end_idx = -1
    for i in range(1, len(lines)):
        if lines[i].strip() == '---':
            end_idx = i
            break
            
    if end_idx != -1:
        return "\n".join(lines[:end_idx+1]) + "\n", "\n".join(lines[end_idx+1:])
    return "", content

def main():
    if '--reusable-only' not in sys.argv:
        print("Usage: agent-harness sync --reusable-only", file=sys.stderr)
        sys.exit(1)
        
    tag = os.environ.get('AGENT_HARNESS_TAG', 'main')
    repo_url = "https://github.com/dayfine/agent-harness.git"
    
    print(f"Fetching upstream from {repo_url} (ref: {tag})...")
    
    with tempfile.TemporaryDirectory() as tmpdir:
        # Clone upstream
        run_cmd(f"git clone -q --depth 1 -b {tag} {repo_url} upstream", cwd=tmpdir)
        upstream_dir = os.path.join(tmpdir, 'upstream')
        
        # Find reusable files
        search_dirs = ['.agents/agents', '.agents/rules', 'dev/lib', '.github/workflows']
        reusable_files = []
        
        for d in search_dirs:
            full_dir = os.path.join(upstream_dir, d)
            if not os.path.exists(full_dir):
                continue
            for root, _, files in os.walk(full_dir):
                for f in files:
                    if f.endswith('.md') or f.endswith('.sh') or f.endswith('.yml'):
                        filepath = os.path.join(root, f)
                        rel_path = os.path.relpath(filepath, upstream_dir)
                        
                        with open(filepath, 'r') as fh:
                            content = fh.read()
                            frontmatter, body = extract_frontmatter(content)
                            
                            # If it's a markdown file in .agents with reusable frontmatter
                            is_reusable_md = (f.endswith('.md') and rel_path.startswith('.agents') and 'harness: reusable' in frontmatter)
                            # Or if it's a script/workflow which are implicitly reusable
                            is_implicit_reusable = rel_path.startswith('dev/lib') or rel_path.startswith('.github/workflows')
                            
                            if is_reusable_md or is_implicit_reusable:
                                reusable_files.append((rel_path, frontmatter, body))
                            
        if not reusable_files:
            print("No reusable files found upstream.")
            return

        synced_count = 0
        skipped_count = 0

        for rel_path, up_frontmatter, up_body in reusable_files:
            if not os.path.exists(rel_path):
                continue
                
            with open(rel_path, 'r') as fh:
                local_content = fh.read()
                
            local_frontmatter, local_body = extract_frontmatter(local_content)
            
            # Combine local frontmatter with upstream body
            if local_frontmatter:
                merged_content = local_frontmatter + up_body
            else:
                # If there's no local frontmatter, use the upstream one completely
                merged_content = up_frontmatter + up_body
            
            if local_content == merged_content:
                continue
                
            print(f"\n--- Changes detected in {rel_path} ---")
            
            # Print diff
            diff = difflib.unified_diff(
                local_content.splitlines(keepends=True),
                merged_content.splitlines(keepends=True),
                fromfile=f"local ({rel_path})",
                tofile=f"upstream ({rel_path})"
            )
            sys.stdout.writelines(diff)
            
            # Prompt
            while True:
                choice = input(f"\nUpdate {rel_path}? [y/N/skip] ").strip().lower()
                if choice in ['y', 'yes']:
                    with open(rel_path, 'w') as fh:
                        fh.write(merged_content)
                    print(f"Updated {rel_path}.")
                    synced_count += 1
                    break
                elif choice in ['n', 'no', 'skip', '']:
                    print(f"Skipped {rel_path}.")
                    skipped_count += 1
                    break
                else:
                    print("Please answer y or n.")
                    
        print(f"\nSync complete. {synced_count} files updated, {skipped_count} files skipped.")

if __name__ == '__main__':
    main()
