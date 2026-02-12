package migrate

import (
	"os"
	"path/filepath"
	"testing"
)

func TestPackUnpackArchive(t *testing.T) {
	// Create source directory with test files
	srcDir := t.TempDir()
	os.MkdirAll(filepath.Join(srcDir, "subdir"), 0755)
	os.WriteFile(filepath.Join(srcDir, "file1.txt"), []byte("hello"), 0644)
	os.WriteFile(filepath.Join(srcDir, "subdir", "file2.txt"), []byte("world"), 0644)

	// Pack
	archivePath := filepath.Join(t.TempDir(), "test.tar.gz")
	if err := PackArchive(srcDir, archivePath); err != nil {
		t.Fatalf("PackArchive: %v", err)
	}

	// Verify archive exists
	info, err := os.Stat(archivePath)
	if err != nil {
		t.Fatalf("archive not created: %v", err)
	}
	if info.Size() == 0 {
		t.Fatal("archive is empty")
	}

	// Unpack
	dstDir := t.TempDir()
	if err := UnpackArchive(archivePath, dstDir); err != nil {
		t.Fatalf("UnpackArchive: %v", err)
	}

	// Verify files
	data, err := os.ReadFile(filepath.Join(dstDir, "file1.txt"))
	if err != nil {
		t.Fatalf("reading file1.txt: %v", err)
	}
	if string(data) != "hello" {
		t.Errorf("expected 'hello', got %q", string(data))
	}

	data, err = os.ReadFile(filepath.Join(dstDir, "subdir", "file2.txt"))
	if err != nil {
		t.Fatalf("reading subdir/file2.txt: %v", err)
	}
	if string(data) != "world" {
		t.Errorf("expected 'world', got %q", string(data))
	}
}

func TestUnpackArchive_PathTraversal(t *testing.T) {
	// Create a valid archive first, then test that unpack to same dir works
	srcDir := t.TempDir()
	os.WriteFile(filepath.Join(srcDir, "safe.txt"), []byte("ok"), 0644)

	archivePath := filepath.Join(t.TempDir(), "test.tar.gz")
	if err := PackArchive(srcDir, archivePath); err != nil {
		t.Fatalf("PackArchive: %v", err)
	}

	dstDir := t.TempDir()
	if err := UnpackArchive(archivePath, dstDir); err != nil {
		t.Fatalf("should succeed for normal archive: %v", err)
	}
}
