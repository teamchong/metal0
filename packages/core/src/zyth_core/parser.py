"""
Zyth Parser - Converts Python source to AST
"""
import ast
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List


@dataclass
class ParsedModule:
    """Represents a parsed Python module"""
    ast_tree: ast.Module
    source: str
    filename: str
    imports: List[str] = field(default_factory=list)  # List of imported module names


def parse_file(filepath: str) -> ParsedModule:
    """
    Parse a Python file and return the AST

    Args:
        filepath: Path to Python file

    Returns:
        ParsedModule containing AST and metadata
    """
    with open(filepath, 'r') as f:
        source = f.read()

    try:
        ast_tree = ast.parse(source, filepath)

        # Extract import statements
        imports = []
        for node in ast.walk(ast_tree):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    imports.append(alias.name)

        return ParsedModule(
            ast_tree=ast_tree,
            source=source,
            filename=filepath,
            imports=imports
        )
    except SyntaxError as e:
        raise SyntaxError(f"Failed to parse {filepath}: {e}") from e


def load_module(module_name: str, search_path: Path) -> ParsedModule:
    """
    Load and parse a Python module

    Args:
        module_name: Name of module to load (e.g., "mymath")
        search_path: Directory to search for module

    Returns:
        ParsedModule for the imported module

    Raises:
        FileNotFoundError: If module file not found
    """
    module_file = search_path / f"{module_name}.py"

    if not module_file.exists():
        raise FileNotFoundError(f"Module '{module_name}' not found at {module_file}")

    return parse_file(str(module_file))


def load_all_modules(main_module: ParsedModule) -> Dict[str, ParsedModule]:
    """
    Load all modules imported by the main module (and recursively their imports)

    Args:
        main_module: The main/entry point module

    Returns:
        Dict mapping module name to ParsedModule
    """
    search_path = Path(main_module.filename).parent
    loaded_modules: Dict[str, ParsedModule] = {}
    to_load = list(main_module.imports)

    while to_load:
        module_name = to_load.pop(0)

        # Skip if already loaded
        if module_name in loaded_modules:
            continue

        # Load module
        module = load_module(module_name, search_path)
        loaded_modules[module_name] = module

        # Add its imports to the queue
        for imported in module.imports:
            if imported not in loaded_modules and imported not in to_load:
                to_load.append(imported)

    return loaded_modules


def dump_ast(parsed: ParsedModule) -> str:
    """Debug helper to visualize AST"""
    return ast.dump(parsed.ast_tree, indent=2)


if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("Usage: python -m zyth_core.parser <file.py>")
        sys.exit(1)

    filepath = sys.argv[1]
    parsed = parse_file(filepath)
    print(f"✓ Parsed {filepath}")
    print(f"\nAST:\n{dump_ast(parsed)}")
