# dev helpers - hot reloading server
.PHONY: install
install:
	yarn install

.PHONY: hot
hot:
	yarn parcel serve example/index.html