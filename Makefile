.PHONY: app debug run test install clean

app:            ## Build release → build/Rastro.app
	@Scripts/build.sh release

debug:          ## Build debug
	@Scripts/build.sh debug

run: debug      ## Build debug e abre o app
	@Scripts/quit.sh
	@open build/Rastro.app

test:           ## Testes do núcleo (git, parser, estatísticas, banco)
	@Scripts/build.sh test

install: app    ## Copia para /Applications
	@Scripts/quit.sh
	@rm -rf /Applications/Rastro.app
	@cp -R build/Rastro.app /Applications/
	@echo "✓ /Applications/Rastro.app"

clean:
	@rm -rf build .build
