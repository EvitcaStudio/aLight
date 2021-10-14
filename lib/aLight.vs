#ENABLE LOCALCLIENTCODE
#BEGIN CLIENTCODE
#BEGIN JAVASCRIPT

// see if you can pass a texture in and bloom it up

(function () {
	let gl;
	let program;
	let foundClient;

	let engineWaitId = setInterval(function() {
		if (VS.Client && !foundClient) {
			foundClient = true;
			buildLight();
			gl = document.getElementById('game_canvas').getContext('webgl2');
		}

		if ((foundClient && gl) && gl.getParameter(gl.CURRENT_PROGRAM)) {
			program = gl.getParameter(gl.CURRENT_PROGRAM);
			clearInterval(engineWaitId);
		}

	});
	
	const lightVertex = `#version 300 es
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
	
	const lightFrag = `#version 300 es
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

	const MAX_LIGHTS = 168;
	const MOUSE_ID = 999999999;
	const LIGHT_INDEX_GAP = 6;

	let buildLight = function() {
		let aLight = {};
		VS.World.global.aLight = aLight;
		VS.Client.aLight = aLight;
		VS.Client.___EVITCA_aLight = true;

		// the game's size
		const gameSize = VS.World.getGameSize();
		
		// array full of lights
		aLight.lights = [];
		// array full of light ids
		aLight.lightIDS = [];
		// array full of the ids of the light in the shader
		aLight.shaderIDS = [];
		// a variable that is a boolean for if the library is in debug mode or not
		aLight.debugging = false;

		aLight.uniforms = {
			'uAmbientColor': 0,
			'uGlobalLight': 0.001, // linux devices need this value to be above 0 to render
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
		}

		aLight.generateToken = function(pTokenLength = 7) {
			var token = '';
			var chars = '0123456789';

			for (var i = 0; i < pTokenLength; i++) {
				token += chars.charAt(Math.floor(Math.random() * chars.length));
			}
			return Number(token);
		}

		aLight.getLightById = function(pID) {
			if (pID) {
				for (var el of this.lights) {
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
		}
		
		aLight.updateShaderMisc = function() {
			let screenPos = VS.Client.getScreenPos();
			let screenScale = VS.Client.getScreenScale();
			let mapView = VS.Client.mapView;
			// let gameSize = VS.World.getGameSize();
			let windowSize = VS.Client.getWindowSize();
			let mousePos = VS.Client.getMousePos();
			VS.Client.setMapView(VS.Client.mapView);
			
			// windowSize
			this.uniforms.uWindowSize.x = windowSize.width;
			this.uniforms.uWindowSize.y = windowSize.height;
			
			// mapView
			this.uniforms.uMapView[0] = (mainM.mapScaleWidth > 1 ? mainM.mapScaleWidth : mapView.scale.x);
			this.uniforms.uMapView[1] = (mainM.mapScaleHeight > 1 ? mainM.mapScaleHeight : mapView.scale.y);
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
		}

		aLight.updateLightUniforms = function(pLight) {
			// 6 indexes per light
			this.uniforms.uLights[(this.uniforms.uLightsCount * LIGHT_INDEX_GAP)] = pLight.xPos;
			this.uniforms.uLights[(this.uniforms.uLightsCount * LIGHT_INDEX_GAP) + 1] = pLight.yPos;
			this.uniforms.uLights[(this.uniforms.uLightsCount * LIGHT_INDEX_GAP) + 2] = pLight.color;
			this.uniforms.uLights[(this.uniforms.uLightsCount * LIGHT_INDEX_GAP) + 3] = pLight.brightness;
			this.uniforms.uLights[(this.uniforms.uLightsCount * LIGHT_INDEX_GAP) + 4] = pLight.size;
			this.uniforms.uLights[(this.uniforms.uLightsCount * LIGHT_INDEX_GAP) + 5] = pLight.shaderID;
			this.uniforms.uLightsCount++;
			if (this.debugging) {
				VS.Client.aMes('aLight [Lights]: ' + this.uniforms.uLightsCount);
			}
		}

		aLight.destroyLight = function(pID) {
			let light = this.getLightById(pID);
			let index = this.uniforms.uLights.indexOf(light.shaderID);
			this.uniforms.uLightsCount--;
			if (light) {
				if (this.lights.includes(light)) {
					this.lights.splice(this.lights.indexOf(light), 1);
				}

				if (this.lightIDS.includes(pID)) {
					this.lightIDS.splice(this.lightIDS.indexOf(pID), 1);
				}

				if (this.shaderIDS.includes(pID)) {
					this.shaderIDS.splice(this.shaderIDS.indexOf(light.shaderID), 1);
				}
				
				for (let i = index; i >= index - (LIGHT_INDEX_GAP-1); i--) {
					this.uniforms.uLights[i] = 0;
				}
			} else {
				console.error('aLight Module: Cannot remove light, no %clight', 'font-weight: bold', 'found with this id.');
				return;
			}
			if (this.debugging) {
				VS.Client.aMes('aLight [Lights]: ' + this.uniforms.uLightsCount);
			}
		}

		aLight.createLight = function(pSettings) {
			if (this.lights.length >= MAX_LIGHTS) {
				if (this.debugging) {
					console.warn('aLight Module: %cMAX_LIGHTS', 'font-weight: bold', 'reached. Aborted');
				}
				return;
			}
			let xPos;
			let yPos;
			let color = 16777215;
			let offset = { 'x': 0, 'y': 0 };
			let size = 1;
			let brightness = 0;
			let id;
			var shaderID;

			shaderID = this.generateToken(9);
			while (this.shaderIDS.includes(shaderID)) {
				shaderID = this.generateToken(9);
			}
			this.shaderIDS.push(shaderID);

			// id 
			if (pSettings?.id) {
				if (typeof(pSettings.id) === 'string' || typeof(pSettings.id) === 'number') {
					id = pSettings.id;
				}
			}

			if (!id) {
				if (this.debugging) {
					console.warn('aLight Module: No %csettings.id', 'font-weight: bold', 'property passed or settings.id was a invalid variable type. Random id generated. (Remember to add a id to your lights, so they are easy to find / remove)');
				}
				id = this.generateToken();
				while (this.lightIDS.includes(id)) {
					id = this.generateToken();
				}
			}

			this.lightIDS.push(id);

			// position
			if ((pSettings?.xPos || pSettings?.xPos === 0) && (pSettings?.yPos || pSettings?.yPos === 0)) {
				if (typeof(pSettings?.xPos) === 'number' || typeof(pSettings?.yPos) === 'number') {
					xPos = pSettings.xPos;
					yPos = pSettings.yPos;
				} else {
					console.error('aLight Module [ID: \'' + id + '\']: Invalid variable type passed for the %csettings.xPos || settings.yPos', 'font-weight: bold', 'property. Aborted');
					return;
				}
			} else {
				if (this.debugging) {
					console.warn('aLight Module [ID: \'' + id + '\']: No %csettings.xPos || settings.yPos', 'font-weight: bold', 'property passed. Aborted');
				}
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
						console.error('aLight Module [ID: \'' + id + '\']: Invalid variable type passed for the %csettings.offset.x || settings.offset.y', 'font-weight: bold', 'property. Aborted');
						return;
					}
				} else {
					if (this.debugging) {
						console.warn('aLight Module [ID: \'' + id + '\']: Invalid variable type passed for the %csettings.offset', 'font-weight: bold', 'property. Aborted');
					}
					return;			
				}
			} else {
				if (this.debugging) {
					console.warn('aLight Module [ID: \'' + id + '\']: No %csettings.offset.x || settings.offset.y', 'font-weight: bold', 'property passed. Reverted to default');
				}
			}

			if (pSettings?.size) {
				if (typeof(pSettings.size) === 'number') {
					size = pSettings.size;
				} else {
					if (this.debugging) {
						console.warn('aLight Module [ID: \'' + id + '\']: Invalid variable type passed for the %csettings.size', 'font-weight: bold', 'property. Reverted to default');
					}
				}
			}

			// color
			if (pSettings?.color) {
				if (typeof(pSettings?.color) === 'number') {
					if (String(pSettings.color).length <= 8) {
						color = Math.round(10*Math.abs(pSettings.color))/10;
					} else {
						if (this.debugging) {
							console.warn('aLight Module [ID: \'' + id + '\']: Invalid %csettings.color format', 'font-weight: bold', 'Expected a decimal color. Reverted to default');
						}
					}
				} else {
					if (this.debugging) {
						console.warn('aLight Module [ID: \'' + id + '\']: Invalid variable type passed for the %csettings.color', 'font-weight: bold', 'property. Reverted to default');
					}
				}
			} else {
				if (this.debugging) {
					console.warn('aLight Module [ID: \'' + id + '\']: No %csettings.color', 'font-weight: bold', 'property passed. Reverted to default');
				}
			}

			// brightness
			if (pSettings?.brightness) {
				if (typeof(pSettings.brightness) === 'number') {
					brightness = pSettings.brightness;
				} else {
					if (this.debugging) {
						console.warn('aLight Module [ID: \'' + id + '\']: Invalid variable type passed for the %csettings.brightness', 'font-weight: bold', 'property. Reverted to default');
					}
				}
			} else {
				if (this.debugging) {
					console.warn('aLight Module [ID: \'' + id + '\']: No %csettings.brightness', 'font-weight: bold', 'property passed. Reverted to default');
				}
			}

			// light
			var light = {};

			light.id = id;
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
		}

		aLight.attachLight = function(pDiob, pSettings) {
			if (pDiob) {
				if (typeof(pDiob) === 'object') {
					if (pSettings) {
						if (typeof(pSettings) === 'object') {
							if (this.lights.length >= MAX_LIGHTS) {
								if (this.debugging) {
									console.warn('aLight Module: %cMAX_LIGHTS', 'font-weight: bold', 'reached. Aborted');
								}
								return;
							}
							if (!pDiob.attachedLights) {
								pDiob.attachedLights = [];
							}
							if (pSettings.xPos === undefined) {
								if (pDiob.xPos || pDiob.xPos === 0) {
									pSettings.xPos = pDiob.xPos;
								}
							}
							if (pSettings.yPos === undefined) {
								if (pDiob.yPos || pDiob.yPos === 0) {
									pSettings.yPos = pDiob.yPos;
								}
							}
							var light = this.createLight(pSettings);
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
		}

		aLight.detachLight = function(pDiob, pID) {
			if (pDiob) {
				if (typeof(pDiob) === 'object') {
					if (pID) {
						if (pDiob.attachedLights) {
							if (typeof(pDiob.attachedLights) === 'object' && pDiob.attachedLights.length !== undefined) {
								let light = this.getLightById(pID);
								if (light.owner) {
									if (light.owner.attachedLights.includes(light)) {
										light.owner.attachedLights.splice(light.owner.attachedLights.indexOf(light), 1);
									}
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
						if (this.debugging) {
							console.warn('aLight Module: No light %cid', 'font-weight: bold', 'passed. Cannot find light. Aborted');
						}
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
		}

		aLight.attachMouseLight = function(pSettings) {
			if (pSettings) {
				if (typeof(pSettings) === 'object') {
					this.createLight(null, pSettings);
				} else {
					console.error('aLight Module: Invalid variable type passed for the %csettings', 'font-weight: bold', 'parameter. Aborted');
					return;
				}

			} else {
				if (this.debugging) {
					console.warn('aLight Module: No %csettings', 'font-weight: bold', 'parameter passed. Reverted to default');
				}
				var mousePos = VS.Client.getMousePos();
				this.createLight(null, {
					'xPos': mousePos.x,
					'yPos': mousePos.y,
					'offset': { 'x': 0, 'y': 0 },
					'color': [1, 1, 1],
					'brightness': 30,
					'size': 30,
					'id': MOUSE_ID
				})
			}
		}

		aLight.detachMouseLight = function() {
			this.destroyLight(MOUSE_ID);
		}

		aLight.adjustGlobalLight = function(pValue) {
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
		}

		aLight.adjustAmbience = function(pAmbience = 0) {
			if (pAmbience || pAmbience === 0) {
				if (typeof(pAmbience) === 'number') {
					if (String(pAmbience).length <= 8) {
						this.uniforms.uAmbientColor = Math.round(pAmbience);
						return;
					} else {
						if (this.debugging) {
							console.warn('aLight Module: Invalid %cambience format', 'font-weight: bold', 'Expected a decimal color. Reverted to default');
						}
						this.uniforms.uAmbientColor = 0;
						return;
					}
				} else {
					console.error('aLight Module: No %cambience', 'font-weight: bold', 'parameter passed. Aborted');
					return;
				}
			} else {
				console.error('aLight Module: Invalid variable type passed for the %cambience', 'font-weight: bold', 'parameter. Aborted');
				return;
			}
		}

		// function to create the shader
		aLight.createLightShader = function(pVertex, pFragment, pUniforms) {
			return new PIXI.Filter(pVertex, pFragment, pUniforms);
		}

		aLight.update = function (pT) {
			this.uniforms.uTime = pT / 300;
			this.updateShaderMisc();
			rafLight = requestAnimationFrame(this.update.bind(this));
		}

		// toggle the debug mode, which allows descriptive text to be shown when things of notice happen
		aLight.toggleDebug = function() {
			this.debugging = (this.debugging ? false : true);
		}

		VS.Client.addFilter('LightShader', 'custom', { 'filter': aLight.createLightShader(lightVertex, lightFrag, aLight.uniforms) });
		var rafLight = requestAnimationFrame(aLight.update.bind(aLight));
		// aLight.toggleDebug();
	}
}
)();
