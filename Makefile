.PHONY: app debug run test install clean

app:            ## Build release → build/DevTimeline.app
	@Scripts/build.sh release

debug:          ## Build debug
	@Scripts/build.sh debug

run: debug      ## Build debug e abre o app
	@Scripts/quit.sh
	@open build/DevTimeline.app

test:           ## Testes do núcleo (git, parser, estatísticas, banco)
	@Scripts/build.sh test

install: app    ## Copia para /Applications
	@Scripts/quit.sh
	@rm -rf /Applications/DevTimeline.app
	@cp -R build/DevTimeline.app /Applications/
	@echo "✓ /Applications/DevTimeline.app"

clean:
	@rm -rf build .build
