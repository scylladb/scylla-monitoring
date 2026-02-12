package targets

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"gopkg.in/yaml.v3"
)

// TargetGroup represents a Prometheus target group with labels.
type TargetGroup struct {
	Targets []string          `yaml:"targets"`
	Labels  map[string]string `yaml:"labels"`
}

// GenerateTargets parses the "dc:ip1,ip2 dc2:ip3" format and generates target groups.
func GenerateTargets(servers []string, cluster string, aliasSeparator string) ([]TargetGroup, error) {
	var allGroups []TargetGroup

	for _, server := range servers {
		groups, err := genTargets(server, cluster, aliasSeparator)
		if err != nil {
			return nil, err
		}
		allGroups = append(allGroups, groups...)
	}

	return allGroups, nil
}

// genTargets parses a single "dc:ip1,ip2" string.
func genTargets(servers, cluster, aliasSeparator string) ([]TargetGroup, error) {
	if !strings.Contains(servers, ":") {
		return nil, fmt.Errorf("server list must contain a dc name (format: dc:ip1,ip2)")
	}

	parts := strings.SplitN(servers, ":", 2)
	dc := parts[0]
	ips := strings.Split(parts[1], ",")

	baseLabels := map[string]string{
		"cluster": cluster,
		"dc":      dc,
	}

	// Separate plain IPs from aliased IPs
	var plainTargets []string
	var aliasedGroups []TargetGroup

	for _, ip := range ips {
		if aliasSeparator != "" && strings.Contains(ip, aliasSeparator) {
			ipParts := strings.SplitN(ip, aliasSeparator, 2)
			labels := make(map[string]string)
			for k, v := range baseLabels {
				labels[k] = v
			}
			labels["instance"] = ipParts[1]
			aliasedGroups = append(aliasedGroups, TargetGroup{
				Targets: []string{ipParts[0]},
				Labels:  labels,
			})
		} else {
			plainTargets = append(plainTargets, ip)
		}
	}

	var result []TargetGroup
	if len(plainTargets) > 0 {
		labels := make(map[string]string)
		for k, v := range baseLabels {
			labels[k] = v
		}
		result = append(result, TargetGroup{
			Targets: plainTargets,
			Labels:  labels,
		})
	}
	result = append(result, aliasedGroups...)

	return result, nil
}

var (
	dcRe = regexp.MustCompile(`^Datacenter: (\S+)\s*$`)
	ipRe = regexp.MustCompile(`\S{2}\s+([\d.]+)\s`)
)

// ParseNodetoolStatus parses the output of `nodetool status` and returns dc:ip1,ip2 strings.
func ParseNodetoolStatus(r io.Reader) ([]string, error) {
	scanner := bufio.NewScanner(r)
	var result []string
	var currentDC string
	var ips []string

	for scanner.Scan() {
		line := scanner.Text()

		if m := dcRe.FindStringSubmatch(line); m != nil {
			if currentDC != "" {
				result = append(result, currentDC+":"+strings.Join(ips, ","))
			}
			currentDC = m[1]
			ips = nil
			continue
		}

		if currentDC != "" {
			if m := ipRe.FindStringSubmatch(line); m != nil {
				ips = append(ips, m[1])
			}
		}
	}

	if currentDC != "" {
		result = append(result, currentDC+":"+strings.Join(ips, ","))
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("reading nodetool output: %w", err)
	}

	return result, nil
}

// WriteTargetsFile writes target groups to a YAML file.
func WriteTargetsFile(groups []TargetGroup, directory, filename string) error {
	if err := os.MkdirAll(directory, 0755); err != nil {
		return fmt.Errorf("creating directory: %w", err)
	}

	data, err := yaml.Marshal(groups)
	if err != nil {
		return fmt.Errorf("marshaling targets: %w", err)
	}

	path := filepath.Join(directory, filename)
	if err := os.WriteFile(path, data, 0644); err != nil {
		return fmt.Errorf("writing targets file: %w", err)
	}

	return nil
}

// WriteTargetsSimple writes a simple target list (no DC labels) to a YAML file.
func WriteTargetsSimple(targets []string, directory, filename string) error {
	if err := os.MkdirAll(directory, 0755); err != nil {
		return fmt.Errorf("creating directory: %w", err)
	}

	groups := []TargetGroup{{Targets: targets}}
	data, err := yaml.Marshal(groups)
	if err != nil {
		return fmt.Errorf("marshaling targets: %w", err)
	}

	path := filepath.Join(directory, filename)
	if err := os.WriteFile(path, data, 0644); err != nil {
		return fmt.Errorf("writing targets file: %w", err)
	}

	return nil
}
