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

		// uniform uLightBlock {
		// 	vec2 pos;
		// 	float color;
		// 	float size;
		// 	bool on;
		// 	vec2 drawPerformanceSettings; // maxDrawDistance, maxDistanceFadeRange
		// } uLight[MAX_LIGHTS];

		// float random (vec2 st) {
		// 	return fract(sin(dot(st.xy, vec2(12.9898, 78.233)))*43758.5453123);
		// }

		// bool prob(float prob) {
		// 	if (random(vec2(gl_FragCoord.xy / uResolution.xy)) <= prob / 100.) {
		// 		return true;
		// 	}
		// 	return false;
		// }

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
		#define LIGHT_INDEX_GAP 6

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
		uniform vec2 uScreenScale;
		uniform vec2 uMapPos;
		uniform vec2 uMousePos;
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
				float xScr = (uLights[i] - uScreenPos.x) + uMapPos.x;
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
				float id = uLights[i+5]; 
				
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
		const MAX_LIGHTS = 168;
		const MOUSE_ID = 999999999;
		const LIGHT_INDEX_GAP = 6;
		const gameSize = VS.World.getGameSize();

		const aLight = {
			// array full of lights
			lights: [],
			// array full of light ids
			lightIDS: [],
			// array full of the ids of the light in the shader
			shaderIDS: [],
			// a variable that is a boolean for if the library is in debug mode or not
			debugging: false,
			'version': '1.0.0',
			// a object holding the delta information used in the update loop
			updateDelta: {},
			uniforms: {
				'uAmbientColor': VS.World.global.aUtils.grabColor('#000000').decimal,
				'uGlobalLight': 0, // linux devices need this value to be above 0 to render?
				'uLights': new Float64Array(1012),
				'uLightsCount': 0,
				'uTime': 0,
				'uScreenPos': { 'x': 0, 'y': 0 },
				'uResolution': { 'x': gameSize.width, 'y': gameSize.height },
				'uWindowSize': { 'x': gameSize.width, 'y': gameSize.height },
				'uMapView': [1, 1, 0.5, 0.5], // scaleX, scaleY, anchor.x, anchor.y
				'uMousePos': { 'x': 1, 'y': 1 },
				'uMapPos': { 'x': 1, 'y': 1 },
				'uScreenScale': { 'x': 1, 'y': 1 }
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
					console.error('aLight Module [ID: \'' + pID + '\']: No %clight', 'font-weight: bold', 'found with that id');
					return;
				} else {
					console.error('aLight Module: No %cid', 'font-weight: bold', 'passed');
					return;
				}
			},
			updateShaderMisc: function() {
				let screenPos = VS.Client.getScreenPos();
				let screenScale = VS.Client.getScreenScale();
				let mapView = VS.Client.mapView;
				let windowSize = VS.Client.getWindowSize();
				let mousePos = VS.Client.getMousePos();
				VS.Client.setMapView(VS.Client.mapView);
				
				// windowSize
				this.uniforms.uWindowSize.x = windowSize.width;
				this.uniforms.uWindowSize.y = windowSize.height;
				
				// mapView
				this.uniforms.uMapView[0] = mainM.mapScaleWidth;
				this.uniforms.uMapView[1] = mainM.mapScaleHeight;
				this.uniforms.uMapView[2] = mapView.anchor.x;
				this.uniforms.uMapView[3] = mapView.anchor.y;

				// screenPos
				this.uniforms.uScreenPos.x = screenPos.x;
				this.uniforms.uScreenPos.y = screenPos.y;

				// mousePos
				this.uniforms.uMousePos.x = mousePos.x;
				this.uniforms.uMousePos.y = mousePos.y;

				// mapPos
				this.uniforms.uMapPos.x = scrM.xMapPos;
				this.uniforms.uMapPos.y = scrM.yMapPos;

				// screenScale
				this.uniforms.uScreenScale.x = screenScale.x;
				this.uniforms.uScreenScale.y = screenScale.y;
			},
			updateLightUniforms: function (pLight) {
				// 6 indexes per light
				this.uniforms.uLights[(this.uniforms.uLightsCount * LIGHT_INDEX_GAP)] = pLight.xPos;
				this.uniforms.uLights[(this.uniforms.uLightsCount * LIGHT_INDEX_GAP) + 1] = pLight.yPos;
				this.uniforms.uLights[(this.uniforms.uLightsCount * LIGHT_INDEX_GAP) + 2] = pLight.color;
				this.uniforms.uLights[(this.uniforms.uLightsCount * LIGHT_INDEX_GAP) + 3] = pLight.brightness;
				this.uniforms.uLights[(this.uniforms.uLightsCount * LIGHT_INDEX_GAP) + 4] = pLight.size;
				this.uniforms.uLights[(this.uniforms.uLightsCount * LIGHT_INDEX_GAP) + 5] = pLight.shaderID;
				this.uniforms.uLightsCount++;
				if (this.debugging) VS.Client.aMes('aLight [Lights]: ' + this.uniforms.uLightsCount);
			},
			destroyLight: function (pID) {
				let light = this.getLightById(pID);
				let index = this.uniforms.uLights.indexOf(light.shaderID);
				this.uniforms.uLightsCount--;
				if (light) {
					if (this.lights.includes(light)) this.lights.splice(this.lights.indexOf(light), 1);
					if (this.lightIDS.includes(pID)) this.lightIDS.splice(this.lightIDS.indexOf(pID), 1);
					if (this.shaderIDS.includes(pID)) this.shaderIDS.splice(this.shaderIDS.indexOf(light.shaderID), 1);
					for (let i = index; i >= index - (LIGHT_INDEX_GAP-1); i--) this.uniforms.uLights[i] = 0;
				} else {
					console.error('aLight Module: Cannot remove light, no %clight', 'font-weight: bold', 'found with this id.');
					return;
				}
				if (this.debugging) VS.Client.aMes('aLight [Lights]: ' + this.uniforms.uLightsCount);
			},
			createLight: function (pSettings) {
				if (this.lights.length >= MAX_LIGHTS) {
					if (this.debugging) console.warn('aLight Module: %cMAX_LIGHTS', 'font-weight: bold', 'reached. Aborted');
					return;
				}
				let xPos;
				let yPos;
				let color = VS.World.global.aUtils.grabColor('#FFFFFF').decimal;
				let offset = { 'x': 0, 'y': 0 };
				let size = 1;
				let brightness = 0;
				let ID;
				let shaderID;

				shaderID = this.generateToken(9);
				while (this.shaderIDS.includes(shaderID)) shaderID = this.generateToken(9);
				this.shaderIDS.push(shaderID);

				// id 
				if (pSettings?.id) {
					if (typeof(pSettings.id) === 'string' || typeof(pSettings.id) === 'number') {
						ID = pSettings.id;
					}
				}

				if (!ID) {
					if (this.debugging) console.warn('aLight Module: No %csettings.id', 'font-weight: bold', 'property passed or settings.id was a invalid variable type. Random id generated. (Remember to add a id to your lights, so they are easy to find / remove)');
					ID = this.generateToken();
					while (this.lightIDS.includes(ID)) ID = this.generateToken();
				}

				this.lightIDS.push(ID);

				// position
				if ((pSettings?.xPos || pSettings?.xPos === 0) && (pSettings?.yPos || pSettings?.yPos === 0)) {
					if (typeof(pSettings?.xPos) === 'number' || typeof(pSettings?.yPos) === 'number') {
						xPos = pSettings.xPos;
						yPos = pSettings.yPos;
					} else {
						console.error('aLight Module [ID: \'' + ID + '\']: Invalid variable type passed for the %csettings.xPos || settings.yPos', 'font-weight: bold', 'property. Aborted');
						return;
					}
				} else {
					if (this.debugging) console.warn('aLight Module [ID: \'' + ID + '\']: No %csettings.xPos || settings.yPos', 'font-weight: bold', 'property passed. Aborted');
					return;
				}
				// offset
				if (pSettings?.offset) {
					if (typeof(pSettings.offset) === 'object') {
						if (typeof(pSettings?.offset.x) === 'number' || typeof(pSettings?.offset.y) === 'number') {
							offset.x = pSettings.offset.x;
							offset.y = pSettings.offset.y;
							xPos+= offset.x;
							yPos-= offset.y;
						} else {
							console.error('aLight Module [ID: \'' + ID + '\']: Invalid variable type passed for the %csettings.offset.x || settings.offset.y', 'font-weight: bold', 'property. Aborted');
							return;
						}
					} else {
						if (this.debugging) console.warn('aLight Module [ID: \'' + ID + '\']: Invalid variable type passed for the %csettings.offset', 'font-weight: bold', 'property. Aborted');
						return;			
					}
				} else {
					if (this.debugging) console.warn('aLight Module [ID: \'' + ID + '\']: No %csettings.offset.x || settings.offset.y', 'font-weight: bold', 'property passed. Reverted to default');
				}

				if (pSettings?.size) {
					if (typeof(pSettings.size) === 'number') {
						size = pSettings.size;
					} else {
						if (this.debugging) console.warn('aLight Module [ID: \'' + ID + '\']: Invalid variable type passed for the %csettings.size', 'font-weight: bold', 'property. Reverted to default');
					}
				}

				// color
				if (pSettings?.color) {
					if (typeof(pSettings?.color) === 'number') {
						color = VS.World.global.aUtils.grabColor(pSettings.color).decimal;
					} else {
						if (this.debugging) console.warn('aLight Module [ID: \'' + ID + '\']: Invalid variable type passed for the %csettings.color', 'font-weight: bold', 'property. Reverted to default');
					}
				} else {
					if (this.debugging) console.warn('aLight Module [ID: \'' + ID + '\']: No %csettings.color', 'font-weight: bold', 'property passed. Reverted to default');
				}

				// brightness
				if (pSettings?.brightness) {
					if (typeof(pSettings.brightness) === 'number') {
						brightness = pSettings.brightness;
					} else {
						if (this.debugging) console.warn('aLight Module [ID: \'' + ID + '\']: Invalid variable type passed for the %csettings.brightness', 'font-weight: bold', 'property. Reverted to default');
					}
				} else {
					if (this.debugging) console.warn('aLight Module [ID: \'' + ID + '\']: No %csettings.brightness', 'font-weight: bold', 'property passed. Reverted to default');
				}

				// light
				let light = {};
				light.id = ID;
				light.shaderID = shaderID;
				light.xPos = xPos;
				light.yPos = yPos;
				light.offset = offset;
				light.color = color;
				light.brightness = brightness;
				light.size = size;
				this.lights.push(light);
				this.updateLightUniforms(light);
				return light;
			},
			attachLight: function (pDiob, pSettings) {
				if (pDiob) {
					if (typeof(pDiob) === 'object') {
						if (pSettings) {
							if (typeof(pSettings) === 'object') {
								if (this.lights.length >= MAX_LIGHTS) {
									if (this.debugging) console.warn('aLight Module: %cMAX_LIGHTS', 'font-weight: bold', 'reached. Aborted');
									return;
								}
								if (!pDiob.attachedLights) {
									pDiob.attachedLights = [];
								}
								if (pSettings.xPos === undefined) {
									if (pDiob.xPos || pDiob.xPos === 0) {
										pSettings.xPos = parseInt(pDiob.xPos) + parseInt(pDiob.xIconOffset);
									}
								}
								if (pSettings.yPos === undefined) {
									if (pDiob.yPos || pDiob.yPos === 0) {
										pSettings.yPos = parseInt(pDiob.yPos) + parseInt(pDiob.xIconOffset);
									}
								}
								let light = this.createLight(pSettings);
								light.owner = pDiob;
								pDiob.attachedLights.push(light);
							} else {
								console.error('aLight Module: Invalid variable type passed for the %csettings', 'font-weight: bold', 'parameter. Aborted');
								return;	
							}
						} else {
							console.error('aLight Module: No %csettings', 'font-weight: bold', 'parameter passed. Aborted');
							return;
						}
					} else {
						console.error('aLight Module: Invalid variable type passed for the %cobject', 'font-weight: bold', 'parameter. Aborted');
						return;					
					}
				} else {
					console.error('aLight Module: No %cobject', 'font-weight: bold', 'parameter passed. Aborted');
					return;
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
										console.error('aLight Module: No %clight', 'font-weight: bold', 'found with that id. Aborted');
										return;
									}
								} else {
									console.error('aLight Module: No %clight', 'font-weight: bold', 'on this diob to remove. Aborted');
									return;
								}
							} else {
								console.error('aLight Module: No %clights', 'font-weight: bold', 'on this diob to remove. Aborted');
								return;
							}
						} else {
							if (this.debugging) console.warn('aLight Module: No light %cid', 'font-weight: bold', 'passed. Cannot find light. Aborted');
							return;
						}
					} else {
						console.error('aLight Module: Invalid variable type passed for the %cdiob', 'font-weight: bold', 'parameter. Aborted');
						return;
					}
				} else {
					console.error('aLight Module: No %cdiob', 'font-weight: bold', 'parameter passed. Cannot remove light from nothing. Aborted');
					return;				
				}
			},
			attachMouseLight: function (pSettings) {
				if (pSettings) {
					if (typeof(pSettings) === 'object') {
						this.createLight(pSettings);
					} else {
						console.error('aLight Module: Invalid variable type passed for the %csettings', 'font-weight: bold', 'parameter. Aborted');
						return;
					}

				} else {
					if (this.debugging) console.warn('aLight Module: No %csettings', 'font-weight: bold', 'parameter passed. Reverted to default');
					let mousePos = VS.Client.getMousePos();
					this.createLight({
						'xPos': mousePos.x,
						'yPos': mousePos.y,
						'offset': { 'x': 0, 'y': 0 },
						'color': VS.World.global.aUtils.grabColor('#FFFFFF').decimal,
						'brightness': 30,
						'size': 30,
						'id': MOUSE_ID
					})
				}
			},
			adjustGlobalLight: function (pValue) {
				if (pValue || pValue === 0) {
					if (typeof(pValue) === 'number') {
						this.uniforms.uGlobalLight = pValue;
					} else {
						console.error('aLight Module: Invalid variable type passed for the %cvalue', 'font-weight: bold', 'parameter. Aborted');
						return;
					}
				} else {
					console.error('aLight Module: No %cvalue', 'font-weight: bold', 'parameter passed. Aborted');
					return;		
				}
			},
			detachMouseLight: function () {
				this.destroyLight(MOUSE_ID);
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
					console.error('aLight Module: Invalid variable type passed for the %cambience', 'font-weight: bold', 'parameter. Aborted');
					return;
				}
			},
			createLightShader: function (pVertex, pFragment, pUniforms) {
				return new PIXI.Filter(pVertex, pFragment, pUniforms);
			}
		};

		VS.World.global.aLight = aLight;
		VS.Client.aLight = aLight;
		VS.Client.___EVITCA_aLight = true;

		let update = (pTimeStamp) => {
			if (aLight.updateDelta.startTime === undefined) aLight.updateDelta.startTime = pTimeStamp;
			aLight.updateDelta.elapsedMS = pTimeStamp - aLight.updateDelta.startTime;
			aLight.uniforms.uTime = aLight.updateDelta.elapsedMS;
			aLight.updateShaderMisc();
			rafLight = requestAnimationFrame(update);
		}

		VS.Client.addFilter('LightShader', 'custom', { 'filter': aLight.createLightShader(aLightVertexShader, aLightFragmentShader, aLight.uniforms) });
		let rafLight = requestAnimationFrame(update);
	}
}
)();
