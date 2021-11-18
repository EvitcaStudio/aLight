#ENABLE LOCALCLIENTCODE
#BEGIN CLIENTCODE
#BEGIN JAVASCRIPT

(() => {
	let gl;
	let program;
	let foundClient;

	let engineWaitId = setInterval(() => {
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
		precision highp float;

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
		precision highp float;
		
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

	let buildLight = () => {
		const MAX_LIGHTS = 204;
		const MOUSE_ID = 999999999;
		const LIGHT_INDEX_GAP = 5;
		const gameSize = VS.World.getGameSize();

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
			// a object holdings the screen's current scale
			gameSize: {},
			// a object holding the screen's current position
			screenPos: {},
			// a object that will hold the position of the middle of the screen on the map, used to help cull lights when they are out of range
			centerScreenPos: {},
			// uniforms that will be passed into the shader to help draw the lights
			uniforms: {
				'uAmbientColor': VS.World.global.aUtils.grabColor('#000000').decimal,
				'uGlobalLight': 0.001, // linux devices need this value to be above 0 to render?
				'uLights': new Float64Array(1012),
				'uLightsCount': 0,
				'uTime': 0,
				'uScreenPos': { 'x': 0, 'y': 0 },
				'uResolution': { 'x': gameSize.width, 'y': gameSize.height },
				'uWindowSize': { 'x': gameSize.width, 'y': gameSize.height },
				'uMapView': [1, 1, 0.5, 0.5], // scaleX, scaleY, anchor.x, anchor.y
				'uMapPos': { 'x': 1, 'y': 1 }
			},
			// toggle the debug mode, which allows descriptive text to be shown when things of notice happen
			toggleDebug: function () {
				this.debugging = (this.debugging ? false : true);
			},
			generateToken: function (pTokenLength = 7) {
				let token = '';
				let chars = '0123456789';

				for (let i = 0; i < pTokenLength; i++) {
					token += chars.charAt(Math.floor(Math.random() * chars.length));
				}
				return Number(token);
			},
			getLightById: function (pID) {
				if (pID) {
					for (let el of this.lights) {
						if (el.id === pID) {
							return el;
						}
					}
					console.error('aLight Module [Light ID: \'' + pID + '\']: No %clight', 'font-weight: bold', 'found with that id');
					return;
				} else {
					console.error('aLight Module: No %cid', 'font-weight: bold', 'passed');
					return;
				}
			},
			updateShaderMisc: function() {
				let mapView = VS.Client.mapView;
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
					let index = (this.lights.indexOf(pLight) * LIGHT_INDEX_GAP);
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
				let light = this.getLightById(pID);
				if (light) {
					if (this.lights.includes(light)) this.lights.splice(this.lights.indexOf(light), 1);
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
				if ((this.lights.length + this.culledLights.length) >= MAX_LIGHTS) {
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
				let cullDistance = -1;
				let fadeDistance = 0;
				let ID;
				let owner;

				// id 
				if (pSettings?.id) {
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
				if (pSettings?.owner) {
					if (typeof(pSettings.owner) === 'object') {
						if ((pSettings.owner.xPos || pSettings.owner.xPos === 0) && (pSettings.owner.yPos || pSettings.owner.yPos === 0)) {
							if (typeof(pSettings.owner.xPos) === 'number' && typeof(pSettings.owner.yPos) === 'number') {
								if (!pSettings.owner.attachedLights) {
									pSettings.owner.attachedLights = [];
								}
								xPos = pSettings.owner.xPos + (pSettings.owner.xIconOffset ? pSettings.owner.xIconOffset : 0);
								yPos = pSettings.owner.yPos + (pSettings.owner.yIconOffset ? pSettings.owner.yIconOffset : 0);
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
					if ((pSettings?.xPos || pSettings?.xPos === 0) && (pSettings?.yPos || pSettings?.yPos === 0)) {
						if (typeof(pSettings?.xPos) === 'number' && typeof(pSettings?.yPos) === 'number') {
							xPos = pSettings.xPos;
							yPos = pSettings.yPos;
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
				if (pSettings?.offset) {
					if (typeof(pSettings.offset) === 'object') {
						if (typeof(pSettings?.offset.x) === 'number' && typeof(pSettings?.offset.y) === 'number') {
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

				if (pSettings?.size) {
					if (typeof(pSettings.size) === 'number') {
						size = pSettings.size;
					} else {
						if (this.debugging) console.warn('aLight Module [Light ID: \'' + ID + '\']: Invalid variable type passed for the %cpSettings.size', 'font-weight: bold', 'property. Reverted to default');
					}
				}

				// color
				if (pSettings?.color) {
					if (typeof(pSettings?.color) === 'number') {
						color = VS.World.global.aUtils.grabColor(pSettings.color).decimal;
					} else {
						if (this.debugging) console.warn('aLight Module [Light ID: \'' + ID + '\']: Invalid variable type passed for the %cpSettings.color', 'font-weight: bold', 'property. Reverted to default');
					}
				} else {
					if (this.debugging) console.warn('aLight Module [Light ID: \'' + ID + '\']: No %cpSettings.color', 'font-weight: bold', 'property passed. Reverted to default');
				}

				// brightness
				if (pSettings?.brightness) {
					if (typeof(pSettings.brightness) === 'number') {
						brightness = pSettings.brightness;
					} else {
						if (this.debugging) console.warn('aLight Module [Light ID: \'' + ID + '\']: Invalid variable type passed for the %cpSettings.brightness', 'font-weight: bold', 'property. Reverted to default');
					}
				} else {
					if (this.debugging) console.warn('aLight Module [Light ID: \'' + ID + '\']: No %cpSettings.brightness', 'font-weight: bold', 'property passed. Reverted to default');
				}

				if (pSettings?.cullDistance) {
					if (typeof(pSettings.cullDistance) === 'number') {
						cullDistance = pSettings.cullDistance;
					} else {
						if (this.debugging) console.warn('aLight Module [Light ID: \'' + ID + '\']: Invalid variable type passed for the %cpSettings.cullDistance', 'font-weight: bold', 'property. Reverted to default');
					}
				}

				if (pSettings?.fadeDistance) {
					if (typeof(pSettings.fadeDistance) === 'number') {
						fadeDistance = pSettings.fadeDistance;
						if (fadeDistance > cullDistance) {
							if (this.debugging) console.warn('aLight Module [Light ID: \'' + ID + '\']: %cpSettings.fadeDistance', 'font-weight: bold', 'is greater than pSettings.cullDistance. pSettings.fadeDistance will not work as expected.');
						}
					} else {
						if (this.debugging) console.warn('aLight Module [Light ID: \'' + ID + '\']: Invalid variable type passed for the %cpSettings.fadeDistance', 'font-weight: bold', 'property. Reverted to default');
					}
				}

				this.reservedLightIDS.push(ID);
				
				// light
				let light = {};
				light.id = ID;
				light.offset = offset;
				light.xPos = xPos + (light.owner ? light.owner.xIconOffset : 0) + light.offset.x;
				light.yPos = yPos + (light.owner ? light.owner.yIconOffset : 0) + light.offset.y;
				light.color = color;
				light.originalBrightness = brightness;
				light.brightness = brightness;
				light.size = size;
				light.cullDistance = cullDistance;
				light.fadeDistance = fadeDistance;
				light.owner = owner;

				this.addLightUniforms(light);

				if (owner) {
					owner.attachedLights.push(light);
					if (!owner.onRelocatedSet) {
						owner._onRelocated = owner.onRelocated;
						owner.onRelocatedSet = true;
						owner.onRelocated = function(pX, pY, pMap, pMove) {
							for (let attachedLight of this.attachedLights) {
								attachedLight.xPos = (this.xPos + this.xIconOffset) + attachedLight.offset.x;
								attachedLight.yPos = (this.yPos + this.yIconOffset) + attachedLight.offset.y;
							}
							if (this._onRelocated) {
								this._onRelocated.apply(this, arguments);
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
								if (typeof(pDiob.attachedLights) === 'object' && pDiob.attachedLights.length !== undefined) {
									let light = this.getLightById(pID);
									if (light.owner) {
										if (light.owner.attachedLights.includes(light)) light.owner.attachedLights.splice(light.owner.attachedLights.indexOf(light), 1);
									}
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
							let mousePos = VS.Client.getMousePos();
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
						let mousePos = VS.Client.getMousePos();
						this.mapPosTracker = {};
						VS.Client.getPosFromScreen(mousePos.x, mousePos.y, this.mapPosTracker);
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
				this.addLightUniforms(pLight);
				this.culledLights.splice(pIndex, 1);
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
			cullFactor: function(pLight, pForceCull) {
				let xCullDistance = Math.abs(this.centerScreenPos.x - pLight.xPos);
				let yCullDistance = Math.abs(this.centerScreenPos.y - pLight.yPos);
				let cullDistanceToUse = (xCullDistance > yCullDistance ? xCullDistance : yCullDistance);
				let scale = VS.World.global.aUtils.normalize(cullDistanceToUse, pLight.cullDistance, pLight.fadeDistance);
				pLight.brightness = VS.Math.clamp(scale * pLight.originalBrightness, -1, pLight.originalBrightness);
				if (VS.World.global.aUtils.round(pLight.brightness) <= 0 || pForceCull) {
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
		aLight.gameSize = VS.World.getGameSize();

		// append code into the client's onMouseMove to update the mouse light if there is one
		if (!VS.Client.onMouseMoveSet) {
			VS.Client._onMouseMove = VS.Client.onMouseMove;
			VS.Client.onMouseMoveSet = true;
			VS.Client.onMouseMove = function(pDiob, pX, pY) {
				if (aLight) {
					if (aLight.mouseLight) {
						this.getPosFromScreen(pX, pY, aLight.mapPosTracker);
						aLight.mouseLight.xPos = aLight.mapPosTracker.x + aLight.mouseLight.offset.x;
						aLight.mouseLight.yPos = aLight.mapPosTracker.y + aLight.mouseLight.offset.y;
						aLight.addLightUniforms(aLight.mouseLight, true);
					}
				}
				if (this._onMouseMove) {
					this._onMouseMove.apply(this, arguments);
				}
			}
		}

		// append code into the client's onWindowResize to update the library's window size object
		if (!VS.Client.onWindowResizeSet) {
			VS.Client._onWindowResize = VS.Client.onWindowResize;
			VS.Client.onWindowResizeSet = true;
			VS.Client.onWindowResize = function(pWidth, pHeight) {
				if (aLight) {
					aLight.windowSize.width = pWidth;
					aLight.windowSize.height = pHeight;
					aLight.uniforms.uWindowSize.x = pWidth;
					aLight.uniforms.uWindowSize.y = pHeight;
				}
				if (this._onWindowResize) {
					this._onWindowResize.apply(this, arguments);
				}
			}
		}

		// append code into the client's onScreenMoved to update the library's screen position object
		if (!VS.Client.onScreenMovedSet) {
			VS.Client._onScreenMoved = VS.Client.onScreenMoved;
			VS.Client.onScreenMovedSet = true;
			VS.Client.onScreenMoved = function(pX, pY, pOldX, pOldY) {
				if (aLight) {
					aLight.screenPos.x = pX;
					aLight.screenPos.y = pY;
					aLight.uniforms.uScreenPos.x = pX;
					aLight.uniforms.uScreenPos.y = pY;
				}
				if (this._onScreenMoved) {
					this._onScreenMoved.apply(this, arguments);
				}
			}
		}

		// update loop that updates the lights and checks if a light needs to be culled
		let update = (pTimeStamp) => {
			if (aLight.updateDelta.startTime === undefined) aLight.updateDelta.startTime = pTimeStamp;
			// the elapsed MS since the start time
			aLight.uniforms.uTime = pTimeStamp - aLight.updateDelta.startTime;
			aLight.updateShaderMisc();

			let xScreenCenter = aLight.screenPos.x + (aLight.gameSize.width / 2);
			let yScreenCenter = aLight.screenPos.y + (aLight.gameSize.height / 2);
			let screenCenterChanged = false;

			// if the screen's center position has changed then we need to try and cull lights if possible, if it did not change from the last frame, no need to try and cull lights, since the last frame would have done it.
			if (xScreenCenter !== aLight.centerScreenPos.x || yScreenCenter !== aLight.centerScreenPos.y) screenCenterChanged = true;
			aLight.centerScreenPos.x = xScreenCenter;
			aLight.centerScreenPos.y = yScreenCenter;

			for (let lightIndex = aLight.lights.length - 1; lightIndex >= 0; lightIndex--) {
				let light = aLight.lights[lightIndex];
				let inCullingRange = Math.abs(aLight.centerScreenPos.x - light.xPos) >= light.cullDistance || Math.abs(aLight.centerScreenPos.y - light.yPos) >= light.cullDistance;

				if (light.fadeDistance) {
					if (inCullingRange) {
						aLight.cullFactor(light, true);
						continue;
					} else {
						if (screenCenterChanged) {
							if (aLight.centerScreenPos.x >= (light.xPos + light.fadeDistance) || aLight.centerScreenPos.x >= Math.abs(light.xPos - light.fadeDistance) || aLight.centerScreenPos.y >= light.yPos + light.fadeDistance || aLight.centerScreenPos.y >= Math.abs(light.yPos - light.fadeDistance)) {
								aLight.cullFactor(light);
							}
						}
					}
				} else {
					if (inCullingRange && light.cullDistance !== -1) {
						aLight.cull(light);
						continue;
					}
				}
				aLight.addLightUniforms(light, true);
			}

			for (let lightIndex = aLight.culledLights.length - 1; lightIndex >= 0; lightIndex--) {
				let light = aLight.culledLights[lightIndex];
				let inCullingRange = Math.abs(aLight.centerScreenPos.x - light.xPos) >= light.cullDistance || Math.abs(aLight.centerScreenPos.y - light.yPos) >= light.cullDistance;
				if (!inCullingRange) {
					aLight.uncull(light, lightIndex);
				}
			}

			rafLight = requestAnimationFrame(update);
		}

		VS.Client.addFilter('LightShader', 'custom', { 'filter': new PIXI.Filter(aLightVertexShader, aLightFragmentShader, aLight.uniforms) });
		let rafLight = requestAnimationFrame(update);
	}
}
)();
