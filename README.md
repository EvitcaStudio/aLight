# aLight  
A powerful plugin to help bring some fabulous lighting to your game.

## Implementation (`Client-Side-Only`)
### Requires [aListener](https://github.com/EvitcaStudio/aListener)  `client-side`  
### Requires [aUtils](https://github.com/EvitcaStudio/aUtils)  `client-side`  
#### #INCLUDE SCRIPT aLight.js  

## How to reference  
### `Javascript`
#### aLight|VS.global.aLight|VS.Client.aLight  
  
### `VyScript`  
#### aLight|Client.aLight

## API   

###  aLight.toggleDebug()
   - `desc`: Turn on/off the debugging mode of this plugin, which throws additional logs/warnings.   

###  aLight.adjustAmbience(pDecimalColor)   
   - `pDecimalColor`: The color in decimal color format  *(eg: `16777215` for the color white)*  `number`  
   - `desc`: The ambience color of the screen  

###  aLight.adjustGlobalLight(pGlobalLight)  
   - `pGlobalLight`: The brightness level of the scene. `-Infinity - Infinity` range.  `0` being completely dark, `1` being completely lit  `number`  
   - `desc`: Adjusts the overall brightness of the scene. *(The scene starts off at a `brightness level of 0` meaning the screen will be black)*     

###  aLight.createLight(pSettings)
   - `pSettings`: The settings this light will use  `object`  
   - `pSettings.xPos`: The xPos at which this light will be placed *uses map position*  `number`  
   - `pSettings.yPos`: The yPos at which this light will be placed *uses map position*  `number`  
   - `pSettings.color`: The color this light will emit in decimal color format  `number`  
   - `pSettings.size`: The size of this light *this works in tandem with pSettings.brightness*  `number`  
   - `pSettings.brightness`: How much light is emitted *this works in tandem with pSettings.size*   `number`  
   - `pSettings.offset`: The offset(s) of this light. If an object is used it will use the object's `.x` and `.y` properties for offsets in each axis. `number|object`      
   - `pSettings.cullDistance`: The `cullingDistance` of this light, when this light is `cullingDistance` away it will be removed from the screen. If an object is used it will use the object's `.x` and `.y` properties for offsets in each axis `number|object`  
   - `pSettings.fadeDistance`: The `fadingDistance` of this light, when this light is `fadingDistance` away it will begin fading out as you move away from it until it reaches the `cullingDistance` and the light is culled. If an object is used it will use the object's `.x` and `.y` properties for offsets in each axis `number|object`     
   - `pSettings.id`: The **unique** name of this light.  
   - `desc`: Creates a light with the inputted settings. This is a `static` light and does not move.

###  aLight.destroyLight(pID)  
   - `pID`: The `id` of the light you want to destroy  
   - `desc`: Destroys the light with the id of `pID`    

###  aLight.attachLight(pDiob, pSettings)  
   - `pDiob`: The diob to attach this light to  `object`
   - `pSettings`: The settings this light will use  `object`  
   - `pSettings.color`: The color this light will emit in decimal color format  `number`  
   - `pSettings.size`: The size of this light *this works in tandem with pSettings.brightness*  `number`  
   - `pSettings.brightness`: How much light is emitted *this works in tandem with pSettings.size*   `number`  
   - `pSettings.center`: To center the light on `pDiob's` icon.  `boolean`  
   - `pSettings.offset`: The offset(s) of this light. If an object is used it will use the object's `.x` and `.y` properties for offsets in each axis. `number|object`      
   - `pSettings.cullDistance`: The `cullingDistance` of this light, when this light is `cullingDistance` away it will be removed from the screen. If an object is used it will use the object's `.x` and `.y` properties for offsets in each axis `number|object`  
   - `pSettings.fadeDistance`: The `fadingDistance` of this light, when this light is `fadingDistance` away it will begin fading out as you move away from it until it reaches the `cullingDistance` and the light is culled. If an object is used it will use the object's `.x` and `.y` properties for offsets in each axis `number|object`     
   - `pSettings.id`: The **unique** name of this light.  
   - `desc`: Attaches a light to `pDiob` with the inputted `pSettings`. Attached lights will follow the things their attached to when they are moved (takes into account `icon offsets`).      

###  aLight.detachLight(pDiob, pID)  
   - `pDiob`: The diob you want to detach a light from  `object`
   - `pID`: The `id` of the light you want to detach  
   - `desc`: Detaches the light with the id of `pID` from `pDiob`  

###  aLight.attachMouseLight(pSettings)  
   - `pSettings`: The settings this light will use  `object`  
   - `pSettings.color`: The color this light will emit in decimal color format  `number`  
   - `pSettings.size`: The size of this light *this works in tandem with pSettings.brightness*  `number`  
   - `pSettings.brightness`: How much light is emitted *this works in tandem with pSettings.size*   `number`  
   - `pSettings.offset`: The offset(s) of this light. If an object is used it will use the object's `.x` and `.y` properties for offsets in each axis. `number|object`      
   - `pSettings.cullDistance`: The `cullingDistance` of this light, when this light is `cullingDistance` away it will be removed from the screen. If an object is used it will use the object's `.x` and `.y` properties for offsets in each axis `number|object`  
   - `pSettings.fadeDistance`: The `fadingDistance` of this light, when this light is `fadingDistance` away it will begin fading out as you move away from it until it reaches the `cullingDistance` and the light is culled. If an object is used it will use the object's `.x` and `.y` properties for offsets in each axis `number|object`     
   - `desc`: Attaches a light to the mouse. When the mouse moves, the light follows the mouse.      

###  aLight.detachMouseLight()  
   - `desc`: Detaches the light from the mouse.  

###  aLight.getLightById(pID)  
   - `pID`: The ID of the light you want to get  
   - `desc`: Returns the light that has the `id` of `pID`   
