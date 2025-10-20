# D2 Diagrams for K3s Homelab

Beautiful, modern architecture diagrams created with [D2](https://d2lang.com/) - a declarative diagramming language.

## Files

- `architecture.d2` - Main cluster architecture with nodes, namespaces, and infrastructure
- `network-endpoints.d2` - Network endpoints, LoadBalancer IPs, and ingress routes

## Installation

### macOS
```bash
brew install d2
```

### Linux
```bash
curl -fsSL https://d2lang.com/install.sh | sh -s --
```

### Windows
Download from https://github.com/terrastruct/d2/releases

## Rendering Diagrams

### Generate SVG (Recommended for GitHub)
```bash
# Architecture diagram
d2 architecture.d2 architecture.svg

# Network endpoints diagram
d2 network-endpoints.d2 network-endpoints.svg
```

### Generate PNG
```bash
# Architecture diagram
d2 architecture.d2 architecture.png

# Network endpoints diagram
d2 network-endpoints.d2 network-endpoints.png
```

### Generate with specific layout engine
D2 supports multiple layout engines for different styles:

```bash
# dagre (default) - hierarchical
d2 --layout dagre architecture.d2 architecture.svg

# elk - good for large graphs
d2 --layout elk architecture.d2 architecture.svg

# tala (paid) - premium layout engine
d2 --layout tala architecture.d2 architecture.svg
```

### With themes
D2 has several built-in themes:

```bash
# Neutral theme (default)
d2 --theme 0 architecture.d2 architecture.svg

# Neutral Grey
d2 --theme 1 architecture.d2 architecture.svg

# Dark theme
d2 --theme 200 architecture.d2 architecture.svg

# Terminal theme
d2 --theme 300 architecture.d2 architecture.svg
```

## Quick Render Script

Save this as `render.sh` for easy rendering:

```bash
#!/bin/bash
# Render all D2 diagrams to SVG

echo "Rendering D2 diagrams..."

d2 architecture.d2 architecture.svg
echo "✓ architecture.svg generated"

d2 network-endpoints.d2 network-endpoints.svg
echo "✓ network-endpoints.svg generated"

echo "Done! Add these to your README:"
echo "  ![Architecture](diagrams/architecture.svg)"
echo "  ![Network Endpoints](diagrams/network-endpoints.svg)"
```

Make it executable:
```bash
chmod +x render.sh
./render.sh
```

## Live Preview While Editing

D2 has a watch mode that auto-regenerates on file changes:

```bash
# Opens browser with live preview
d2 --watch architecture.d2 architecture.svg
```

## VS Code Integration

Install the D2 extension for syntax highlighting and preview:

1. Open VS Code
2. Go to Extensions (Cmd+Shift+X)
3. Search for "D2"
4. Install **D2 Language Support** by Terrastruct

## Editing the Diagrams

The D2 syntax is simple and readable:

```d2
# Nodes
my_node: My Node Label

# Styled nodes
my_node: {
  label: "My Node"
  shape: rectangle
  style.fill: "#bbdefb"
  style.stroke: "#1565c0"
}

# Connections
node1 -> node2: "Label"

# Containers
container: My Container {
  child1: Child Node 1
  child2: Child Node 2
}
```

## Add to README

After rendering, add the diagrams to your README:

```markdown
## Architecture

![K3s Homelab Architecture](diagrams/architecture.svg)

## Network Endpoints

![Network Endpoints](diagrams/network-endpoints.svg)
```

## Why D2?

✅ **Beautiful output** - Modern, professional-looking diagrams
✅ **Code-based** - Version control friendly, easy to review changes
✅ **Fast** - Quick rendering, watch mode for live preview
✅ **Flexible** - Multiple themes and layout engines
✅ **Open source** - Free and actively maintained
✅ **Simple syntax** - Easy to learn and edit

## Resources

- Official Docs: https://d2lang.com/
- Playground: https://play.d2lang.com/
- Examples: https://d2lang.com/tour/intro
- GitHub: https://github.com/terrastruct/d2

## Troubleshooting

**Command not found after install?**
```bash
# Make sure it's in your PATH
export PATH="$HOME/.local/bin:$PATH"
```

**SVG not rendering on GitHub?**
- GitHub supports SVG, but make sure the file is committed
- Try PNG if SVG has issues
- Check file permissions

**Want higher quality PNG?**
```bash
# Increase scale
d2 --scale 2 architecture.d2 architecture.png
```
