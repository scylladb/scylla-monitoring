package migrate

import (
	"archive/tar"
	"compress/gzip"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// PackArchive creates a tar.gz archive from a source directory.
func PackArchive(sourceDir, outputPath string) error {
	outFile, err := os.Create(outputPath)
	if err != nil {
		return fmt.Errorf("creating archive file: %w", err)
	}
	defer outFile.Close()

	gzWriter := gzip.NewWriter(outFile)
	defer gzWriter.Close()

	tarWriter := tar.NewWriter(gzWriter)
	defer tarWriter.Close()

	return filepath.Walk(sourceDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		relPath, err := filepath.Rel(sourceDir, path)
		if err != nil {
			return err
		}
		if relPath == "." {
			return nil
		}

		header, err := tar.FileInfoHeader(info, "")
		if err != nil {
			return fmt.Errorf("creating tar header for %s: %w", relPath, err)
		}
		header.Name = relPath

		if err := tarWriter.WriteHeader(header); err != nil {
			return fmt.Errorf("writing tar header for %s: %w", relPath, err)
		}

		if info.IsDir() {
			return nil
		}

		f, err := os.Open(path)
		if err != nil {
			return fmt.Errorf("opening %s: %w", path, err)
		}
		defer f.Close()

		if _, err := io.Copy(tarWriter, f); err != nil {
			return fmt.Errorf("writing %s to archive: %w", relPath, err)
		}

		return nil
	})
}

// UnpackArchive extracts a tar.gz archive to a destination directory.
func UnpackArchive(archivePath, destDir string) error {
	f, err := os.Open(archivePath)
	if err != nil {
		return fmt.Errorf("opening archive: %w", err)
	}
	defer f.Close()

	gzReader, err := gzip.NewReader(f)
	if err != nil {
		return fmt.Errorf("creating gzip reader: %w", err)
	}
	defer gzReader.Close()

	tarReader := tar.NewReader(gzReader)

	for {
		header, err := tarReader.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("reading tar entry: %w", err)
		}

		// Prevent path traversal
		target := filepath.Join(destDir, header.Name)
		if !strings.HasPrefix(filepath.Clean(target), filepath.Clean(destDir)) {
			return fmt.Errorf("invalid tar entry: path traversal detected: %s", header.Name)
		}

		switch header.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(target, 0755); err != nil {
				return fmt.Errorf("creating directory %s: %w", target, err)
			}
		case tar.TypeReg:
			if err := os.MkdirAll(filepath.Dir(target), 0755); err != nil {
				return fmt.Errorf("creating parent directory for %s: %w", target, err)
			}
			outFile, err := os.Create(target)
			if err != nil {
				return fmt.Errorf("creating file %s: %w", target, err)
			}
			if _, err := io.Copy(outFile, tarReader); err != nil {
				outFile.Close()
				return fmt.Errorf("extracting %s: %w", target, err)
			}
			outFile.Close()
			if err := os.Chmod(target, os.FileMode(header.Mode)); err != nil {
				return fmt.Errorf("setting permissions on %s: %w", target, err)
			}
		}
	}

	return nil
}
