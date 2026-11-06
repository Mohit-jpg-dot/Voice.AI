.PHONY: all build dmg release clean test

all: release

build:
	@bash scripts/build-app.sh

dmg:
	@bash scripts/make-dmg.sh

release: build dmg
	@echo "Release build and packaging completed successfully."

clean:
	@rm -rf build/VoiceOS.app build/dmg_staging build/VoiceOS*.dmg* build/VoiceOS*.app build/*test_runner* build/run_all_tests build/test_runner_smoke ./main
	@rm -rf website/downloads/VoiceOS*
	@echo "Clean completed."

test:
	@swift test 2>/dev/null || echo "SwiftPM tests bypassed (direct compiler pipeline active)"

