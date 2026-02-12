package dashboard

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"unicode/utf8"
)

// Generator orchestrates dashboard generation from templates and types.
type Generator struct {
	Types         map[string]interface{}
	Version       []int
	VersionName   string
	Products      []string
	ExactMatch    map[string]interface{}
	Replacements  [][2]string
	Grafana4      bool
}

// NewGenerator creates a new dashboard generator.
func NewGenerator(typesData []byte) (*Generator, error) {
	var types map[string]interface{}
	if err := json.Unmarshal(typesData, &types); err != nil {
		return nil, fmt.Errorf("parsing types.json: %w", err)
	}
	return &Generator{
		Types:      types,
		ExactMatch: map[string]interface{}{},
	}, nil
}

// SetVersion sets the ScyllaDB version for dashboard generation.
func (g *Generator) SetVersion(version string) {
	g.VersionName = version
	g.Version = ParseVersion(version)
}

// SetReplacements sets the string replacements to apply to generated JSON.
func (g *Generator) SetReplacements(replacements [][2]string) {
	g.Replacements = replacements
}

// ParseReplacements creates replacement pairs from key=value strings.
func ParseReplacements(replace []string) [][2]string {
	var results [][2]string
	for _, v := range replace {
		parts := strings.SplitN(v, "=", 2)
		if len(parts) == 2 {
			results = append(results, [2]string{parts[0], parts[1]})
		} else if len(parts) == 1 {
			results = append(results, [2]string{parts[0], ""})
		}
	}
	return results
}

// Generate generates a dashboard from a template file.
// Returns the dashboard JSON (just the "dashboard" object, ready for Grafana).
func (g *Generator) Generate(templateData []byte) ([]byte, error) {
	var result map[string]interface{}
	if err := json.Unmarshal(templateData, &result); err != nil {
		return nil, fmt.Errorf("parsing template: %w", err)
	}

	idCounter := 1
	UpdateObject(result, g.Types, g.Version, g.Products, g.ExactMatch, &idCounter)

	if !g.Grafana4 {
		ConvertToGrafana5Layout(result)
	}

	dashboard, ok := result["dashboard"]
	if !ok {
		return nil, fmt.Errorf("template missing 'dashboard' key")
	}

	// Use a custom encoder to avoid escaping <, >, & as unicode escapes,
	// matching Python's json.dumps behavior.
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	enc.SetIndent("", "    ")
	if err := enc.Encode(dashboard); err != nil {
		return nil, fmt.Errorf("marshaling dashboard: %w", err)
	}
	// Encoder adds a trailing newline; trim it to match MarshalIndent behavior
	output := bytes.TrimRight(buf.Bytes(), "\n")

	// Python json.dumps uses ensure_ascii=True by default, which escapes
	// non-ASCII characters. Match that behavior.
	output = escapeNonASCII(output)

	// Apply string replacements
	s := string(output)
	for _, r := range g.Replacements {
		s = strings.ReplaceAll(s, r[0], r[1])
		if strings.HasSuffix(r[0], "_DOT__") {
			dashed := strings.ReplaceAll(r[0], "_DOT__", "_DASHED__")
			dashedVal := strings.ReplaceAll(r[1], ".", "-")
			s = strings.ReplaceAll(s, dashed, dashedVal)
		}
	}

	return []byte(s), nil
}

// GenerateToFile generates a dashboard and writes it to a file.
func (g *Generator) GenerateToFile(templateData []byte, outputPath string) error {
	output, err := g.Generate(templateData)
	if err != nil {
		return err
	}

	dir := filepath.Dir(outputPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("creating output directory: %w", err)
	}

	if err := os.WriteFile(outputPath, output, 0644); err != nil {
		return fmt.Errorf("writing dashboard: %w", err)
	}

	return nil
}

// LoadExactMatchFiles loads replacement mappings from JSON or YAML files.
func LoadExactMatchFiles(files []string) (map[string]interface{}, error) {
	result := map[string]interface{}{}
	for _, f := range files {
		data, err := os.ReadFile(f)
		if err != nil {
			return nil, fmt.Errorf("reading replace file %s: %w", f, err)
		}
		var m map[string]interface{}
		if err := json.Unmarshal(data, &m); err != nil {
			return nil, fmt.Errorf("parsing replace file %s: %w", f, err)
		}
		for k, v := range m {
			result[k] = v
		}
	}
	return result, nil
}

// escapeNonASCII replaces non-ASCII characters with \uXXXX escapes,
// matching Python's json.dumps(ensure_ascii=True) behavior.
func escapeNonASCII(data []byte) []byte {
	var buf bytes.Buffer
	buf.Grow(len(data))
	for i := 0; i < len(data); {
		r, size := utf8.DecodeRune(data[i:])
		if r > 127 {
			if r <= 0xFFFF {
				fmt.Fprintf(&buf, "\\u%04x", r)
			} else {
				// Encode as surrogate pair for characters above BMP
				r -= 0x10000
				high := 0xD800 + (r>>10)&0x3FF
				low := 0xDC00 + r&0x3FF
				fmt.Fprintf(&buf, "\\u%04x\\u%04x", high, low)
			}
		} else {
			buf.WriteByte(data[i])
		}
		i += size
	}
	return buf.Bytes()
}

// MergeTypesFiles loads and merges multiple types files.
func MergeTypesFiles(files []string) (map[string]interface{}, error) {
	result := map[string]interface{}{}
	for _, f := range files {
		data, err := os.ReadFile(f)
		if err != nil {
			return nil, fmt.Errorf("reading types file %s: %w", f, err)
		}
		var m map[string]interface{}
		if err := json.Unmarshal(data, &m); err != nil {
			return nil, fmt.Errorf("parsing types file %s: %w", f, err)
		}
		for k, v := range m {
			result[k] = v
		}
	}
	return result, nil
}
