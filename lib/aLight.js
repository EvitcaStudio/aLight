(() => {
	let gl;
	let program;
	let foundClient;
	// Client Library
	const engineWaitId = setInterval(() => {
		if (VS.Client && VS.Client.___EVITCA_aUtils && !foundClient && VS.World.global) {
			foundClient = true;
			buildLight();
			gl = document.getElementById('game_canvas').getContext('webgl2');
		}

		if ((foundClient && gl) && gl.getParameter(gl.CURRENT_PROGRAM)) {
			program = gl.getParameter(gl.CURRENT_PROGRAM);
			clearInterval(engineWaitId);
		}
	});
	
	const aLightVertexShader = `#version 300 es
		precision lowp float;

		in vec2 aVertexPosition;
		out vec2 vTextureCoord;

		uniform mat3 projectionMatrix;
		uniform vec4 inputSize;
		uniform vec4 outputFrame;

		vec4 filterVertexPosition( void ) {
			vec2 position = aVertexPosition * max(outputFrame.zw, vec2(0.)) + outputFrame.xy;
			return vec4((projectionMatrix * vec3(position, 1.)).xy, 0., 1.);
		}

		vec2 filterTextureCoord( void ) {
			return aVertexPosition * (outputFrame.zw * inputSize.zw);
		}

		void main(void) {
			gl_Position = filterVertexPosition();
			vTextureCoord = filterTextureCoord();
		}
		`
	
	const aLightFragmentShader = `#version 300 es
		precision lowp float;
		
		#define MAX_LIGHTS 1012
		#define LIGHT_INDEX_GAP 5

		in vec2 vTextureCoord;

		// built in uniforms
		uniform highp vec4 inputSize;
		uniform highp vec4 outputFrame;

		// light uniforms
		uniform sampler2D uSampler;
		uniform int uLightsCount;
		uniform float uAmbientColor;
		uniform float uGlobalLight;
		uniform float uLights[MAX_LIGHTS];

		// misc
		uniform vec4 uMapView;
		uniform vec2 uWindowSize;
		uniform vec2 uResolution;
		uniform vec2 uScreenPos;
		uniform vec2 uMapPos;
		uniform float uTime;

		out vec4 fragColor;
		
		void main() {
			float uLAR = float((int(uAmbientColor) / (256*256))) / 255.;
			float uLAG = float((int(uAmbientColor) / 256 % 256)) / 255.;
			float uLAB = float((int(uAmbientColor) % 256)) / 255.;
	
			vec3 color = vec3(uLAR, uLAG, uLAB);
			vec4 textureColor = texture(uSampler, vTextureCoord.xy);
			
			for (int i = 0; i <= (uLightsCount*LIGHT_INDEX_GAP); i+=LIGHT_INDEX_GAP) {
				// light pos
				float xScr = (uLights[i+0] - uScreenPos.x) + uMapPos.x;
				float yScr = (uLights[i+1] - uScreenPos.y) + uMapPos.y;
				
				float rWidth = uMapView.x <= 1. ? ((uWindowSize.x - uResolution.x) / uMapView.z / 4.) : 0.;
				float rHeight = uMapView.y <= 1. ? ((uWindowSize.y - uResolution.y) / uMapView.w / 4.) : 0.;

				float x = ((xScr + rWidth) * uMapView.x);
				float y = (uWindowSize.y - (yScr + rHeight) * uMapView.y);

				vec2 lightPos = vec2(x, y);

				// convert decimal color value to rgb
				// light color
				float uLR = float((int(uLights[i+2]) / (256*256))) / 255.;
				float uLG = float((int(uLights[i+2]) / 256 % 256)) / 255.;
				float uLB = float((int(uLights[i+2]) % 256)) / 255.;

				vec3 lightColor = vec3(uLR, uLG, uLB);
				float brightness = uLights[i+3] * uMapView.x;

				// light misc
				float size = -uLights[i+4] * uMapView.x;
				
				// calculate light size / color
				vec2 dis = gl_FragCoord.xy - lightPos;
				vec3 calcColor;
				float str = 1./(sqrt(pow(dis.x, 2.) + pow(dis.y, 2.) + pow(size, 2.)));
				calcColor += vec3(str) * lightColor;
				color += vec3(calcColor) * (lightColor + brightness);
			}

			fragColor = vec4(textureColor.rgb * (color + uGlobalLight), uGlobalLight);
		}
		`

	const buildLight = () => {
		const MAX_LIGHTS = 204;
		const MOUSE_ID = 999999999;
		const LIGHT_INDEX_GAP = 5;
		const MAX_ELAPSED_MS = VS.Client.maxFPS ? (1000 / VS.Client.maxFPS) * 2 : 33.34;
		const TICK_FPS = VS.Client.maxFPS ? (1000 / VS.Client.maxFPS) : 16.67;
		const TILE_SIZE = VS.World.getTileSize();
		const GAME_SIZE = VS.World.getGameSize();
		const aLight = {
			// array full of lights
			lights: [],
			// array full of light ids, used to prevent multiple lights from using the same ID. This ensures that when you use `getLightById` you get the correct light
			reservedLightIDS: [],
			// array of lights that have been culled
			culledLights: [],
			// a variable that is a boolean for if the library is in debug mode or not
			debugging: false,
			// the version of this library
			version: '1.0.0',
			// a object holding the delta information used in the update loop
			updateDelta: {},
			// a object holding the window's size
			windowSize: {},
			// a object holding the screen's current position
			screenPos: {},
			// a object that will hold the position of the middle of the screen on the map, used to help cull lights when they are out of range
			centerScreenPos: {},
			// a object that stores the icon sizes of icons used in this library
			cachedResourcesInfo: {},
			// a object that stores the delta information
			updateDelta: {
				'lastTime': 0,
				'deltaTime': 0,
				'elapsedMS': 0
			},
			assignIconSize: function(pDiob, pAnchor) {
				const infoWasPreset = pDiob.aIconInfo ? true : false;
				const resourceID = (pDiob.atlasName + '_' + (pDiob.iconName ? pDiob.iconName : '') + '_' + (pDiob.iconState ? pDiob.iconState : '')).trim();
				pDiob.aIconInfo = {};

				if (this.cachedResourcesInfo[resourceID]) {
					if (pAnchor) pDiob.anchor = { 'x': this.cachedResourcesInfo[resourceID].halfWidth / this.cachedResourcesInfo[resourceID].width, 'y': this.cachedResourcesInfo[resourceID].halfHeight / this.cachedResourcesInfo[resourceID].height };
					pDiob.aIconInfo = JSON.parse(JSON.stringify(this.cachedResourcesInfo[resourceID]));
					// only needed to get the updated anchor information and icon information from an icon change.
					if (infoWasPreset) return;
				} else {
					pDiob.aIconInfo.width = Math.round(TILE_SIZE.width);
					pDiob.aIconInfo.height = Math.round(TILE_SIZE.height);
					pDiob.aIconInfo.halfWidth = Math.round(TILE_SIZE.width/2);
					pDiob.aIconInfo.halfHeight = Math.round(TILE_SIZE.height/2);
					if (pAnchor) pDiob.anchor = { 'x': pDiob.aIconInfo.halfWidth / pDiob.aIconInfo.width, 'y': pDiob.aIconInfo.halfHeight / pDiob.aIconInfo.height };
				}
				
				const setIconSize = function() {
					const iconSize = VS.Icon.getIconSize(pDiob.atlasName, pDiob.iconName);
					this.cachedResourcesInfo[resourceID] = {
						'width': Math.round(iconSize.width),
						'height': Math.round(iconSize.height),
						'halfWidth': Math.round(iconSize.width / 2),
						'halfHeight': Math.round(iconSize.height / 2)
					};
					pDiob.aIconInfo.width = this.cachedResourcesInfo[resourceID].width;
					pDiob.aIconInfo.height = this.cachedResourcesInfo[resourceID].height;
					pDiob.aIconInfo.halfWidth = this.cachedResourcesInfo[resourceID].halfWidth;
					pDiob.aIconInfo.halfHeight = this.cachedResourcesInfo[resourceID].halfHeight;
					if (pAnchor) pDiob.anchor = { 'x': this.cachedResourcesInfo[resourceID].halfWidth / this.cachedResourcesInfo[resourceID].width, 'y': this.cachedResourcesInfo[resourceID].halfHeight / this.cachedResourcesInfo[resourceID].height };
				}
				if (pDiob.atlasName) {
					VS.Resource.loadResource('icon', pDiob.atlasName, setIconSize.bind(this));
				} else {
					console.warn('aLight Module [assignIconSize]: No %cpDiob.atlasName', 'font-weight: bold', 'to load.');
				}
			},
			// uniforms that will be passed into the shader to help draw the lights
			uniforms: {
				'uAmbientColor': VS.World.global.aUtils.grabColor('#000000').decimal,
				'uGlobalLight': 0.001, // linux devices need this value to be above 0 to render?
				'uLights': new Float64Array(1012),
				'uLightsCount': 0,
				'uTime': 0,
				'uScreenPos': { 'x': 0, 'y': 0 },
				'uResolution': { 'x': GAME_SIZE.width, 'y': GAME_SIZE.height },
				'uWindowSize': { 'x': GAME_SIZE.width, 'y': GAME_SIZE.height },
				'uMapView': [1, 1, 0.5, 0.5], // scaleX, scaleY, anchor.x, anchor.y
				'uMapPos': { 'x': 1, 'y': 1 }
			},
			// update loop that updates the lights and checks if a light needs to be culled
			update: function(pElapsedMS, pDeltaTime) {
				// the elapsed MS since the start time
				this.uniforms.uTime = Date.now() - this.updateDelta.startTime;
				this.updateShaderMisc();

				const xScreenCenter = this.screenPos.x + (GAME_SIZE.width / 2);
				const yScreenCenter = this.screenPos.y + (GAME_SIZE.height / 2);
				let screenCenterChanged;

				// if the screen's center position has changed then we need to try and cull lights if possible, if it did not change from the last frame, no need to try and cull lights, since the last frame would have done it.
				if (xScreenCenter !== this.centerScreenPos.x) { 
					screenCenterChanged = 'x';
				}
				if (yScreenCenter !== this.centerScreenPos.y) {
					if (screenCenterChanged) {
						screenCenterChanged = 'xy';
					} else {
						screenCenterChanged = 'y';
					}
				}
				this.centerScreenPos.x = xScreenCenter;
				this.centerScreenPos.y = yScreenCenter;

				for (let lightIndex = this.lights.length - 1; lightIndex >= 0; lightIndex--) {
					const light = this.lights[lightIndex];
					if (light === this.mouseLight) {
						this.addLightUniforms(light, true);
						continue;
					}

					const inCullingRange = Math.abs(this.centerScreenPos.x - light.xPos) >= (light.cullDistance.x / VS.Client.mapView.scale.x) || Math.abs(this.centerScreenPos.y - light.yPos) >= (light.cullDistance.y / VS.Client.mapView.scale.x);

					if ((light.fadeDistance.x || light.fadeDistance.y) && screenCenterChanged && (light.cullDistance.x !== -1 && light.cullDistance.y !== -1)) {
						if (inCullingRange) {
							this.cullFactor(light, true, screenCenterChanged);
							continue;
						} else {
							const centerScreenLeft = this.centerScreenPos.x <= light.xPos - (light.fadeDistance.x / VS.Client.mapView.scale.x);
							const centerScreenRight = this.centerScreenPos.x >= light.xPos + (light.fadeDistance.x / VS.Client.mapView.scale.x);
							const centerScreenDown = this.centerScreenPos.y >= light.yPos + (light.fadeDistance.y / VS.Client.mapView.scale.y);
							const centerScreenUp = this.centerScreenPos.y <= light.yPos - (light.fadeDistance.y / VS.Client.mapView.scale.y);

							if (screenCenterChanged === 'x') {
								if (centerScreenRight || centerScreenLeft) {
									this.cullFactor(light, false, screenCenterChanged);
								}
							} else if (screenCenterChanged === 'y') {
								if (centerScreenDown || centerScreenUp) {
									this.cullFactor(light, false, screenCenterChanged);
								}
							} else if (screenCenterChanged === 'xy') {
								if (centerScreenRight || centerScreenLeft || centerScreenDown || centerScreenUp) {
									this.cullFactor(light, false, screenCenterChanged);
								}
							}
						}
					} else {
						if (inCullingRange && (light.cullDistance.x !== -1 && light.cullDistance.y !== -1)) {
							this.cull(light);
							continue;
						}
					}
					this.addLightUniforms(light, true);
				}

				for (let lightIndex = this.culledLights.length - 1; lightIndex >= 0; lightIndex--) {
					const light = this.culledLights[lightIndex];
					const inCullingRange = Math.abs(this.centerScreenPos.x - light.xPos) >= (light.cullDistance.x / VS.Client.mapView.scale.x) || Math.abs(this.centerScreenPos.y - light.yPos) >= (light.cullDistance.y / VS.Client.mapView.scale.y);
					if (!inCullingRange) {
						this.uncull(light, lightIndex);
					}
				}
			},
			// toggle the debug mode, which allows descriptive text to be shown when things of notice happen
			toggleDebug: function () {
				this.debugging = !this.debugging;
			},
			generateToken: function (pTokenLength = 7) {
				let token = '';
				const chars = '0123456789';

				for (let i = 0; i < pTokenLength; i++) {
					token += chars.charAt(Math.floor(Math.random() * chars.length));
				}
				return Number(token);
			},
			getLightById: function (pID) {
				if (pID) {
					for (const el of this.lights) {
						if (el.id === pID) {
							return el;
						}
					}
					return;
				} else {
					console.error('aLight Module: No %cid', 'font-weight: bold', 'passed');
					return;
				}
			},
			updateShaderMisc: function() {
				const mapView = VS.Client.mapView;
				VS.Client.setMapView(VS.Client.mapView);
		
				// mapView
				this.uniforms.uMapView[0] = mainM.mapScaleWidth;
				this.uniforms.uMapView[1] = mainM.mapScaleHeight;
				this.uniforms.uMapView[2] = mapView.anchor.x;
				this.uniforms.uMapView[3] = mapView.anchor.y;

				// mapPos
				this.uniforms.uMapPos.x = scrM.xMapPos;
				this.uniforms.uMapPos.y = scrM.yMapPos;
			},
			removeLightUniforms: function(pLight) {
				if (pLight) {
					this.lights.splice(this.lights.indexOf(pLight), 1);
				} else {
					console.error('aLight Module: No %cpLight', 'font-weight: bold', 'parameter found');
					return;
				}
				this.uniforms.uLightsCount--;
				this.uniforms.uLights.forEach((pElement, pIndex, pArray) => { if (pElement !== 0) pArray[pIndex] = 0; });
				for (let index = 0, count = 0; index < this.lights.length * LIGHT_INDEX_GAP; index += LIGHT_INDEX_GAP, count++) {
					this.uniforms.uLights[index + 0] = this.lights[count].xPos;
					this.uniforms.uLights[index + 1] = this.lights[count].yPos;
					this.uniforms.uLights[index + 2] = this.lights[count].color;
					this.uniforms.uLights[index + 3] = this.lights[count].brightness;
					this.uniforms.uLights[index + 4] = this.lights[count].size;
				}
			},
			addLightUniforms: function (pLight, pRefresh) {
				if (pLight) {
					if (!pRefresh) {
						this.lights.push(pLight);
						this.uniforms.uLightsCount++;
						if (this.debugging) VS.Client.aMes('aLight [Active Lights]: ' + this.uniforms.uLightsCount + ' aLight [Culled Lights]: ' + this.culledLights.length);
					}
					const index = (this.lights.indexOf(pLight) * LIGHT_INDEX_GAP);
					this.uniforms.uLights[index + 0] = pLight.xPos;
					this.uniforms.uLights[index + 1] = pLight.yPos;
					this.uniforms.uLights[index + 2] = pLight.color;
					this.uniforms.uLights[index + 3] = pLight.brightness;
					this.uniforms.uLights[index + 4] = pLight.size;
				} else {
					console.error('aLight Module: No %cpLight', 'font-weight: bold', 'parameter found');
				}
			},
			destroyLight: function (pID) {
				const light = this.getLightById(pID);
				if (light) {
					if (this.reservedLightIDS.includes(pID)) this.reservedLightIDS.splice(this.reservedLightIDS.indexOf(pID), 1);
					if (light.owner) {
						if (light.owner.attachedLights.includes(light)) light.owner.attachedLights.splice(light.owner.attachedLights.indexOf(light), 1);
					}
					this.removeLightUniforms(light);
				} else {
					console.error('aLight Module: Cannot remove light, no %clight', 'font-weight: bold', 'found with this id.');
					return;
				}
				if (this.debugging) VS.Client.aMes('aLight [Active Lights]: ' + this.uniforms.uLightsCount + ' aLight [Culled Lights]: ' + this.culledLights.length);
			},
			createLight: function (pSettings) {
				if (this.lights.length/*  + this.culledLights.length */ >= MAX_LIGHTS) {
					if (this.debugging) console.error('aLight Module: %cMAX_LIGHTS', 'font-weight: bold', 'reached.');
					return;
				}
				if (!pSettings || typeof(pSettings) !== 'object') return;

				let xPos;
				let yPos;
				let color = VS.World.global.aUtils.grabColor('#FFFFFF').decimal;
				let brightness = 0;
				let offset = { 'x': 0, 'y': 0 };
				let size = 1;
				// a value of -1 for the x and y means it will not be apart of the culling system
				let cullDistance = { 'x': -1, 'y': -1 };
				let fadeDistance = { 'x': 0, 'y': 0 };
				let ID;
				let owner;
				// id
				// string or number
				if (pSettings.id) {
					if (typeof(pSettings.id) === 'string' || typeof(pSettings.id) === 'number') {
						ID = pSettings.id;
						if (this.reservedLightIDS.includes(ID)) {
							console.error('aLight Module: %cpSettings.id [\'' + ID + '\']', 'font-weight: bold', 'Is already being used by another light (Remember to add a unique ID to your lights, so they are easy to find / remove) Separate lights cannot share the same ID');
							return;
						}
					}
				} else {
					console.error('aLight Module: No %cpSettings.id', 'font-weight: bold', 'property passed. Lights must have an ID set');
					return;
				}

				// position
				if (pSettings.owner) {
					if (typeof(pSettings.owner) === 'object') {
						if ((pSettings.owner.xPos || pSettings.owner.xPos === 0) && (pSettings.owner.yPos || pSettings.owner.yPos === 0)) {
							if (typeof(pSettings.owner.xPos) === 'number' && typeof(pSettings.owner.yPos) === 'number') {
								if (!pSettings.owner.attachedLights) {
									pSettings.owner.attachedLights = [];
								}
								if (pSettings.center) {
									this.assignIconSize(pSettings.owner);
									xPos = pSettings.owner.getTrueCenterPos().x;
									yPos = pSettings.owner.getTrueCenterPos().y;
								} else {
									xPos = pSettings.owner.xPos;
									yPos = pSettings.owner.yPos;
								}
								owner = pSettings.owner;
							} else {
								console.error('aLight Module [Light ID: \'' + ID + '\']: Invalid variable type passed for the %pSettings.owner.xPos || pSettings.owner.yPos', 'font-weight: bold', 'property.');
								return;
							}
						} else {
							console.error('aLight Module [Light ID: \'' + ID + '\']: No %cpSettings.owner.xPos || pSettings.owner.yPos', 'font-weight: bold', 'property passed. Or it was an invalid type.');
							return;
						}
					} else {
						console.error('aLight Module [Light ID: \'' + ID + '\']: Invalid variable type passed for the %cpSettings.owner', 'font-weight: bold', 'property.');
						return;
					}
				} else {
					if ((pSettings.xPos || pSettings.xPos === 0) && (pSettings.yPos || pSettings.yPos === 0)) {
						if (typeof(pSettings.xPos) === 'number' && typeof(pSettings.yPos) === 'number') {
							xPos = pSettings.xPos + TILE_SIZE.width / 2;
							yPos = pSettings.yPos + TILE_SIZE.height / 2;
						} else {
							console.error('aLight Module [Light ID: \'' + ID + '\']: Invalid variable type passed for the %cpSettings.xPos || pSettings.yPos', 'font-weight: bold', 'property.');
							return;
						}
					} else {
						console.error('aLight Module [Light ID: \'' + ID + '\']: No %cpSettings.xPos || pSettings.yPos', 'font-weight: bold', 'property passed. Or it was an invalid type.');
						return;
					}
				}
				// offset
				// num or object with `x` and `y` as numbers
				if (pSettings.offset) {
					if (typeof(pSettings.offset) === 'number') {
						offset.x = pSettings.offset;
						offset.y = pSettings.offset;
					} else if (typeof(pSettings.offset) === 'object') {
						if (typeof(pSettings.offset.x) === 'number' && typeof(pSettings.offset.y) === 'number') {
							offset.x = pSettings.offset.x;
							offset.y = pSettings.offset.y;
						} else {
							console.error('aLight Module [Light ID: \'' + ID + '\']: Invalid variable type passed for the %cpSettings.offset.x || pSettings.offset.y', 'font-weight: bold', 'property.');
							return;
						}
					} else {
						console.error('aLight Module [Light ID: \'' + ID + '\']: Invalid variable type passed for the %cpSettings.offset', 'font-weight: bold', 'property.');
						return;			
					}
				} else {
					if (this.debugging) console.warn('aLight Module [Light ID: \'' + ID + '\']: No %cpSettings.offset.x || pSettings.offset.y', 'font-weight: bold', 'property passed. Reverted to default');
				}

				if (pSettings.size) {
					if (typeof(pSettings.size) === 'number') {
						size = pSettings.size;
					} else {
						if (this.debugging) console.warn('aLight Module [Light ID: \'' + ID + '\']: Invalid variable type passed for the %cpSettings.size', 'font-weight: bold', 'property. Reverted to default');
					}
				}

				// color
				// decimal
				if (pSettings.color) {
					if (typeof(pSettings.color) === 'number') {
						color = VS.World.global.aUtils.grabColor(pSettings.color).decimal;
					} else {
						if (this.debugging) console.warn('aLight Module [Light ID: \'' + ID + '\']: Invalid variable type passed for the %cpSettings.color', 'font-weight: bold', 'property. Reverted to default');
					}
				} else {
					if (this.debugging) console.warn('aLight Module [Light ID: \'' + ID + '\']: No %cpSettings.color', 'font-weight: bold', 'property passed. Reverted to default');
				}

				// brightness
				// num
				if (pSettings.brightness) {
					if (typeof(pSettings.brightness) === 'number') {
						brightness = pSettings.brightness;
					} else {
						if (this.debugging) console.warn('aLight Module [Light ID: \'' + ID + '\']: Invalid variable type passed for the %cpSettings.brightness', 'font-weight: bold', 'property. Reverted to default');
					}
				} else {
					if (this.debugging) console.warn('aLight Module [Light ID: \'' + ID + '\']: No %cpSettings.brightness', 'font-weight: bold', 'property passed. Reverted to default');
				}

				// num or object with `x` and `y` as numbers
				if (pSettings.cullDistance) {
					if (typeof(pSettings.cullDistance) === 'number') {
						cullDistance.x = pSettings.cullDistance / VS.Client.mapView.scale.x;
						cullDistance.y = pSettings.cullDistance / VS.Client.mapView.scale.y;
					} else if (typeof(pSettings.cullDistance) === 'object') {
						if (typeof(pSettings.cullDistance.x) === 'number' && typeof(pSettings.cullDistance.y) === 'number') {
							cullDistance.x = pSettings.cullDistance.x / VS.Client.mapView.scale.x;
							cullDistance.y = pSettings.cullDistance.y / VS.Client.mapView.scale.y;
						} else {
							console.error('aLight Module [Light ID: \'' + ID + '\']: Invalid variable type passed for the %cpSettings.cullDistance.x || pSettings.cullDistance.y', 'font-weight: bold', 'property.');
							return;
						}
					} else {
						console.error('aLight Module [Light ID: \'' + ID + '\']: Invalid variable type passed for the %cpSettings.cullDistance', 'font-weight: bold', 'property.');
						return;			
					}
				}
				// num or object with `x` and `y` as numbers
				if (pSettings.fadeDistance) {
					if (typeof(pSettings.fadeDistance) === 'number') {
						fadeDistance.x = pSettings.fadeDistance / VS.Client.mapView.scale.x;
						fadeDistance.y = pSettings.fadeDistance / VS.Client.mapView.scale.y;
						if (fadeDistance.x > cullDistance.x || fadeDistance.y > cullDistance.y) {
							if (this.debugging) console.warn('aLight Module [Light ID: \'' + ID + '\']: %cpSettings.fadeDistance', 'font-weight: bold', 'is greater than pSettings.cullDistance. pSettings.fadeDistance will not work as expected.');
						}
					} else if (typeof(pSettings.fadeDistance) === 'object') {
						if (typeof(pSettings.fadeDistance.x) === 'number' && typeof(pSettings.fadeDistance.y) === 'number') {
							fadeDistance.x = pSettings.fadeDistance.x / VS.Client.mapView.scale.x;
							fadeDistance.y = pSettings.fadeDistance.y / VS.Client.mapView.scale.y;
							if (fadeDistance.x > cullDistance.x || fadeDistance.y > cullDistance.y) {
								if (this.debugging) console.warn('aLight Module [Light ID: \'' + ID + '\']: %cpSettings.fadeDistance', 'font-weight: bold', 'is greater than pSettings.cullDistance. pSettings.fadeDistance will not work as expected.');
							}
						} else {
							console.error('aLight Module [Light ID: \'' + ID + '\']: Invalid variable type passed for the %cpSettings.fadeDistance.x || pSettings.fadeDistance.y', 'font-weight: bold', 'property.');
							return;
						}
					} else {
						console.error('aLight Module [Light ID: \'' + ID + '\']: Invalid variable type passed for the %cpSettings.fadeDistance', 'font-weight: bold', 'property.');
						return;			
					}
				}

				this.reservedLightIDS.push(ID);
				
				// light
				const light = {};
				light.owner = owner;
				light.id = ID;
				light.offset = offset;
				light.xPos = xPos + light.offset.x;
				light.yPos = yPos + light.offset.y;
				light.color = color;
				light.originalBrightness = brightness;
				light.brightness = brightness;
				light.size = size;
				light.cullDistance = cullDistance;
				light.fadeDistance = fadeDistance;
				this.addLightUniforms(light);

				if (owner) {
					owner.attachedLights.push(light);
					if (!owner.aLightOnRelocatedSet) {
						owner._aLightOnRelocated = owner.onRelocated;
						owner.aLightOnRelocatedSet = true;
						owner.onRelocated = function(pX, pY, pMap, pMove) {
							for (const attachedLight of this.attachedLights) {
								attachedLight.xPos = this.getTrueCenterPos().x + attachedLight.offset.x;
								attachedLight.yPos = this.getTrueCenterPos().y + attachedLight.offset.y;
							}
							if (this._aLightOnRelocated) {
								this._aLightOnRelocated.apply(this, arguments);
							}
						}
					}
				}
				return light;
			},
			detachLight: function (pDiob, pID) {
				if (pDiob) {
					if (typeof(pDiob) === 'object') {
						if (pID) {
							if (pDiob.attachedLights) {
								if (pDiob.attachedLights.constructor === Array) {
									const light = this.getLightById(pID);
									if (light) {
										// destroy light since we are detaching it
										this.destroyLight(light.id);
									} else {
										console.error('aLight Module: No %clight', 'font-weight: bold', 'found with that id.');
										return;
									}
								} else {
									console.error('aLight Module: No %clight', 'font-weight: bold', 'on this diob to remove.');
									return;
								}
							} else {
								console.error('aLight Module: No %clights', 'font-weight: bold', 'on this diob to remove.');
								return;
							}
						} else {
							console.error('aLight Module: No light %cid', 'font-weight: bold', 'passed. Cannot find light.');
							return;
						}
					} else {
						console.error('aLight Module: Invalid variable type passed for the %cdiob', 'font-weight: bold', 'parameter.');
						return;
					}
				} else {
					console.error('aLight Module: No %cdiob', 'font-weight: bold', 'parameter passed. Cannot remove light from nothing.');
					return;				
				}
			},
			attachLight: function (pDiob, pSettings) {
				pSettings.owner = pDiob;
				this.createLight(pSettings);
			},
			detachMouseLight: function () {
				this.destroyLight(MOUSE_ID);
				this.mouseLight = null;
			},
			attachMouseLight: function (pSettings) {
				if (!this.mouseLight) {
					if (pSettings) {
						if (typeof(pSettings) === 'object') {
							const mousePos = VS.Client.getMousePos();
							this.mapPosTracker = {};
							VS.Client.getPosFromScreen(mousePos.x, mousePos.y, this.mapPosTracker);
							pSettings.xPos = this.mapPosTracker.x;
							pSettings.yPos = this.mapPosTracker.y;
							pSettings.id = MOUSE_ID;
							this.mouseLight = this.createLight(pSettings);
						} else {
							console.error('aLight Module: Invalid variable type passed for the %cpSettings', 'font-weight: bold', 'parameter.');
							return;
						}

					} else {
						if (this.debugging) console.warn('aLight Module: No %cpSettings', 'font-weight: bold', 'parameter passed. Reverted to default');
						const mousePos = VS.Client.getMousePos();
						this.mapPosTracker = {};
						VS.Client.getPosFromScreen(mousePos.x, mousePos.y, this.mapPosTracker);
						if (Number.isNaN(this.mapPosTracker.x) || Number.isNaN(this.mapPosTracker.y)) {
							this.mapPosTracker.x = 0;
							this.mapPosTracker.y = 0;
						}
						this.mouseLight = this.createLight({
							'xPos': this.mapPosTracker.x,
							'yPos': this.mapPosTracker.y,
							'offset': { 'x': 0, 'y': 0 },
							'color': VS.World.global.aUtils.grabColor('#FFFFFF').decimal,
							'brightness': 30,
							'size': 15,
							'id': MOUSE_ID
						});
					}
				} else {
					console.error('aLight Module: There is already a light attached to the %cmouse', 'font-weight: bold');
				}
			},
			uncull: function(pLight, pIndex) {
				this.culledLights.splice(pIndex, 1);
				this.addLightUniforms(pLight);
				if (aLight.debugging) VS.Client.aMes('aLight [Active Lights]: ' + this.uniforms.uLightsCount + ' aLight [Culled Lights]: ' + this.culledLights.length);
			},
			cull: function(pLight) {
				// if this light is the mouse light it cannot be culled, skip to the next light
				if (this.mouseLight)
					if (pLight === this.mouseLight) return;

				this.removeLightUniforms(pLight);
				this.culledLights.push(pLight);
				if (aLight.debugging) VS.Client.aMes('aLight [Active Lights]: ' + this.uniforms.uLightsCount + ' aLight [Culled Lights]: ' + this.culledLights.length);
			},
			cullFactor: function(pLight, pForceCull, pDimensionChanged) {
				const xDistance = Math.abs(this.centerScreenPos.x - pLight.xPos);
				const yDistance = Math.abs(this.centerScreenPos.y - pLight.yPos);
				let scale;
				if (pDimensionChanged === 'x') {
					scale = VS.World.global.aUtils.normalize(xDistance, (pLight.cullDistance.x / VS.Client.mapView.scale.x), (pLight.fadeDistance.x / VS.Client.mapView.scale.x));
				} else if (pDimensionChanged === 'y') {
					scale = VS.World.global.aUtils.normalize(yDistance, (pLight.cullDistance.y / VS.Client.mapView.scale.y), (pLight.fadeDistance.y / VS.Client.mapView.scale.y));
				} else if (pDimensionChanged === 'xy') {
					const dimensionToUse = (xDistance > yDistance ? 'xDistance' : 'yDistance');
					const cullDistanceToUse = (dimensionToUse === 'xDistance' ? xDistance : yDistance);
					scale = VS.World.global.aUtils.normalize(cullDistanceToUse, (dimensionToUse === 'xDistance' ? (pLight.cullDistance.x / VS.Client.mapView.scale.x) : (pLight.cullDistance.y / VS.Client.mapView.scale.y)), (dimensionToUse === 'xDistance' ? (pLight.fadeDistance.x / VS.Client.mapView.scale.x) : (pLight.fadeDistance.y / VS.Client.mapView.scale.y)));
				}
				if (pDimensionChanged) pLight.brightness = VS.Math.clamp(scale * pLight.originalBrightness, -1, pLight.originalBrightness);
				if (VS.World.global.aUtils.round(pLight.brightness) <= 0 || pForceCull) {
					pLight.brightness = -1;
					this.cull(pLight);
				}
			},
			adjustGlobalLight: function (pValue) {
				if (pValue || pValue === 0) {
					if (typeof(pValue) === 'number') {
						this.uniforms.uGlobalLight = pValue;
					} else {
						console.error('aLight Module: Invalid variable type passed for the %cvalue', 'font-weight: bold', 'parameter.');
						return;
					}
				} else {
					console.error('aLight Module: No %cvalue', 'font-weight: bold', 'parameter passed.');
					return;		
				}
			},
			adjustAmbience: function (pAmbience = 0) {
				if (pAmbience || pAmbience === 0) {
					if (typeof(pAmbience) === 'number') {
						this.uniforms.uAmbientColor = VS.World.global.aUtils.grabColor(pAmbience).decimal;
					} else {
						console.error('aLight Module: Invalid %cambience format', 'font-weight: bold', 'Expected a decimal color. Reverted to default');
						return;
					}
				} else {
					console.error('aLight Module: Invalid variable type passed for the %cambience', 'font-weight: bold', 'parameter.');
					return;
				}
			}
		};

		VS.World.global.aLight = aLight;
		VS.Client.aLight = aLight;
		VS.Client.___EVITCA_aLight = true;

		VS.Client.getScreenPos(aLight.screenPos);
		VS.Client.getWindowSize(aLight.windowSize);

		if (typeof(VS.Client.mapView.scale) !== 'object') {
			VS.Client.mapView.scale = { 'x': VS.Client.mapView.scale, 'y': VS.Client.mapView.scale };
		}

		VS.Client.mapView.anchor = { 'x': 0.5, 'y': 0.5 };
		VS.Client.setMapView(VS.Client.mapView);

		if (VS.Client.timeScale === undefined) {
			VS.Client.timeScale = 1;
		}

		const prototypeDiob = VS.newDiob();
		if (!prototypeDiob.constructor.prototype.aCenterPos && !prototypeDiob.constructor.prototype.getTrueCenterPos) {
			prototypeDiob.constructor.prototype.aCenterPos = { 'x': 0, 'y': 0 };
			prototypeDiob.constructor.prototype.getTrueCenterPos = function() {
				const tileSize = VS.World.getTileSize();
				this.aCenterPos.x = Math.round(this.xPos + (this.aIconInfo ? this.aIconInfo.halfWidth : tileSize.width) + this.xIconOffset);
				this.aCenterPos.y = Math.round(this.yPos + (this.aIconInfo ? this.aIconInfo.halfHeight : tileSize.height) + this.yIconOffset);
				return this.aCenterPos;
			};
		}
		VS.delDiob(prototypeDiob);
		
		if (!aLight.onScreenRenderSet) {
			aLight._onScreenRender = VS.Client.onScreenRender;
			aLight.onScreenRenderSet = true;
			VS.Client.onScreenRender = function(pT) {
				if (this.___EVITCA_aPause) {
					if (this.aPause.paused) {
						this.aLight.updateDelta.lastTime = pT;
						return;
					}
				}
				if (this.aLight.updateDelta.startTime === undefined) this.aLight.updateDelta.startTime = Date.now();
				if (pT > this.aLight.updateDelta.lastTime) {
					this.aLight.updateDelta.elapsedMS = pT - this.aLight.updateDelta.lastTime;
					if (this.aLight.updateDelta.elapsedMS > MAX_ELAPSED_MS) {
						// check here, if warnings are showing up about setInterval taking too long
						this.aLight.updateDelta.elapsedMS = MAX_ELAPSED_MS;
					}
					this.aLight.updateDelta.deltaTime = (this.aLight.updateDelta.elapsedMS / TICK_FPS) * this.timeScale;
					this.aLight.updateDelta.elapsedMS *= this.timeScale;
				}

				this.aLight.update(this.aLight.updateDelta.elapsedMS, this.aLight.updateDelta.deltaTime);
				this.aLight.updateDelta.lastTime = pT;			
				if (this.aLight._onScreenRender) {
					this.aLight._onScreenRender.apply(this, arguments);
				}
			}
		}

		// append code into the client's onMouseMove to update the mouse light if there is one
		if (!aLight.onMouseMoveSet) {
			aLight._onMouseMove = VS.Client.onMouseMove;
			aLight.onMouseMoveSet = true;
			VS.Client.onMouseMove = function(pDiob, pX, pY) {
				if (aLight) {
					if (aLight.mouseLight) {
						this.getPosFromScreen(pX, pY, aLight.mapPosTracker);
						aLight.mouseLight.xPos = aLight.mapPosTracker.x + aLight.mouseLight.offset.x;
						aLight.mouseLight.yPos = aLight.mapPosTracker.y + aLight.mouseLight.offset.y;
						aLight.addLightUniforms(aLight.mouseLight, true);
					}
				}
				if (this.aLight._onMouseMove) {
					this.aLight._onMouseMove.apply(this, arguments);
				}
			}
		}

		// append code into the client's onWindowResize to update the library's window size object
		if (!aLight.onWindowResizeSet) {
			aLight._onWindowResize = VS.Client.onWindowResize;
			aLight.onWindowResizeSet = true;
			VS.Client.onWindowResize = function(pWidth, pHeight) {
				if (aLight) {
					aLight.windowSize.width = pWidth;
					aLight.windowSize.height = pHeight;
					aLight.uniforms.uWindowSize.x = pWidth;
					aLight.uniforms.uWindowSize.y = pHeight;
				}
				if (this.aLight._onWindowResize) {
					this.aLight._onWindowResize.apply(this, arguments);
				}
			}
		}

		// append code into the client's onScreenMoved to update the library's screen position object
		if (!aLight.onScreenMovedSet) {
			aLight._onScreenMoved = VS.Client.onScreenMoved;
			aLight.onScreenMovedSet = true;
			VS.Client.onScreenMoved = function(pX, pY, pOldX, pOldY) {
				if (aLight) {
					aLight.screenPos.x = pX;
					aLight.screenPos.y = pY;
					aLight.uniforms.uScreenPos.x = pX;
					aLight.uniforms.uScreenPos.y = pY;
				}
				if (this.aLight._onScreenMoved) {
					this.aLight._onScreenMoved.apply(this, arguments);
				}
			}
		}

		VS.Client.addFilter('LightShader', 'custom', { 'filter': new PIXI.Filter(aLightVertexShader, aLightFragmentShader, aLight.uniforms) });
	}
}
)();
