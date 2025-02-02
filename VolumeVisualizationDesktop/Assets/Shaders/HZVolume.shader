﻿/*
* Copyright 2019 Idaho National Laboratory.
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*      http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/



// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

/* HZ Volume Shader | Marko Sterbentz 6/19/2017
 * A vert/frag shader for rendering data bricks that use HZ-ordered data
 */
Shader "Custom/HZVolume"
{
	Properties
	{
		_MainTex("Texture", 2D) = "white" {}											// An array of bytes that is the 8-bit raw data. It is essentially a 1D array/texture.
		_VolumeDataTexture("3D Data Texture", 3D) = "" {}
		_NormPerRay("Intensity Normalization per Ray" , Float) = 1
		_Steps("Max Number of Steps", Range(1,1024)) = 128
		_TransferFunctionTex("Transfer Function", 2D) = "white" {}
		_ClippingPlaneNormal("Clipping Plane Normal", Vector) = (1, 0, 0)
		_ClippingPlanePosition("Clipping Plane Position", Vector) = (0.5, 0.5, 0.5)
		_ClippingPlaneEnabled("Clipping Plane Enabled", Int) = 0						// A "boolean" for whether the clipping plane is active or not. 0 == false, 1 == true
		_BrickSize("Brick Size", Int) = 0
		_CurrentZLevel("Current Z Render Level", Int) = 0
		_MaxZLevel("Max Z Render Level", Int) = 0
		_LastBitMask("Last Bit Mask", Int) = 0

		// data slicing clipping planes and thresholding (X, Y, Z are user coordinates) (landon wooley)
		_SliceAxisXMin("Slice along axis X: min", Range(0,1)) = 0
		_SliceAxisXMax("Slice along axis X: max", Range(0,1)) = 1
		_SliceAxisYMin("Slice along axis Y: min", Range(0,1)) = 0
		_SliceAxisYMax("Slice along axis Y: max", Range(0,1)) = 1
		_SliceAxisZMin("Slice along axis Z: min", Range(0,1)) = 0
		_SliceAxisZMax("Slice along axis Z: max", Range(0,1)) = 1
	}

	SubShader
	{
		Tags
		{
			"Queue" = "Transparent"	   /* Allow transparent surfaces to render. */
			"RenderType" = "Transparent"
		}

		Blend One OneMinusSrcAlpha	// Needed for rendering transparent surfaces.
		Cull Off
		ZTest LEqual
		ZWrite Off
		Fog { Mode off }

		Pass
		{
			CGPROGRAM
			#pragma target 3.0
			#pragma vertex vert
			#pragma fragment frag

			#pragma multi_compile USING_RAW_DATA USING_HZ_DATA
			#pragma multi_compile BIT_8 BIT_16

			#include "UnityCG.cginc"

			/********************* DATA *********************/
			sampler2D _MainTex;
			sampler3D _VolumeDataTexture;
			sampler2D _TransferFunctionTex;
			float _NormPerRay;
			float _Steps;
			float3 _ClippingPlaneNormal;
			float3 _ClippingPlanePosition;
			int _ClippingPlaneEnabled;
			int _BrickSize;
			int _CurrentZLevel;
			int _MaxZLevel;
			int _LastBitMask;

			// Defines a sub-volume of data in which to render data
			float           _SliceAxisXMin, _SliceAxisXMax;
			float           _SliceAxisYMin, _SliceAxisYMax;
			float           _SliceAxisZMin, _SliceAxisZMax;

			//static uint LAST_BIT_MASK = (1 << 24);

			/******************** STRUCTS ********************/

			struct appdata {
				float4 pos : POSITION;
				float2 texcoord : TEXCOORD0;
			};

			struct v2f {
				float4 pos : SV_POSITION;
				float3 ray_o : TEXCOORD1;		// ray origin
				float3 ray_d : TEXCOORD2;		// ray direction
			};

			/******************* FUNCTIONS *******************/

			// Calculates intersection between a ray and a box
			bool IntersectBox(float3 ray_o, float3 ray_d, float3 boxMin, float3 boxMax, out float tNear, out float tFar)
			{
				// Compute intersection of ray with all six bbox planes
				float3 invR = 1.0 / ray_d;
				float3 tBot = invR * (boxMin.xyz - ray_o);
				float3 tTop = invR * (boxMax.xyz - ray_o);
				
				// Re-order intersections to find smallest and largest on each axis
				float3 tMin = min(tTop, tBot);
				float3 tMax = max(tTop, tBot);
				
				// Find the largest tMin and the smallest tMax
				float2 t0 = max(tMin.xx, tMin.yz);
				float largest_tMin = max(t0.x, t0.y);
				t0 = min(tMax.xx, tMax.yz);
				float smallest_tMax = min(t0.x, t0.y);
				
				// Check for hit
				bool hit = (largest_tMin <= smallest_tMax);
				tNear = largest_tMin;
				tFar = smallest_tMax;
				return hit;
			}

			// vertex program
			v2f vert(appdata i)
			{
				v2f o;

				o.pos = UnityObjectToClipPos(i.pos);
				o.ray_d = -ObjSpaceViewDir(i.pos);
				o.ray_o = i.pos.xyz - o.ray_d;
				
				return o;
			}

			/***************************************** HZ CURVING CODE ************************************************/
			uint Compact1By2(uint x)
			{
				x &= 0x09249249;                  // x = ---- 9--8 --7- -6-- 5--4 --3- -2-- 1--0
				x = (x ^ (x >> 2)) & 0x030c30c3; // x = ---- --98 ---- 76-- --54 ---- 32-- --10
				x = (x ^ (x >> 4)) & 0x0300f00f; // x = ---- --98 ---- ---- 7654 ---- ---- 3210
				x = (x ^ (x >> 8)) & 0xff0000ff; // x = ---- --98 ---- ---- ---- ---- 7654 3210
				x = (x ^ (x >> 16)) & 0x000003ff; // x = ---- ---- ---- ---- ---- --98 7654 3210
				return x;
			}

			uint DecodeMorton3X(uint code)
			{
				return Compact1By2(code >> 2);
			}

			uint DecodeMorton3Y(uint code)
			{
				return Compact1By2(code >> 1);
			}

			uint DecodeMorton3Z(uint code)
			{
				return Compact1By2(code >> 0);
			}

			uint3 decode(uint c)
			{
				uint3 cartEquiv = uint3(0,0,0);
				c = c << 1 | 1;
				uint i = c | c >> 1;
				i |= i >> 2;
				i |= i >> 4;
				i |= i >> 8;
				i |= i >> 16;

				i -= i >> 1;

				c *= _LastBitMask / i;
				c &= (~_LastBitMask);
				cartEquiv.x = DecodeMorton3X(c);
				cartEquiv.y = DecodeMorton3Y(c);
				cartEquiv.z = DecodeMorton3Z(c);

				return cartEquiv;
			}

			// Expands an 8-bit integer into 24 bits by inserting 2 zeros after each bit
			// Taken from: https://webcache.googleusercontent.com/search?q=cache:699-OSphYRkJ:https://fgiesen.wordpress.com/2009/12/13/decoding-morton-codes/+&cd=1&hl=en&ct=clnk&gl=us
			uint Part1By2(uint x)
			{
				x &= 0x000003ff;                  // x = ---- ---- ---- ---- ---- --98 7654 3210
				x = (x ^ (x << 16)) & 0xff0000ff; // x = ---- --98 ---- ---- ---- ---- 7654 3210
				x = (x ^ (x << 8)) & 0x0300f00f;  // x = ---- --98 ---- ---- 7654 ---- ---- 3210
				x = (x ^ (x << 4)) & 0x030c30c3;  // x = ---- --98 ---- 76-- --54 ---- 32-- --10
				x = (x ^ (x << 2)) & 0x09249249;  // x = ---- 9--8 --7- -6-- 5--4 --3- -2-- 1--0
				return x;
			}

			// Calculates a 24-bit Morton code for the given 3D point located within the unit cube [0, 1]
			// Taken from: https://devblogs.nvidia.com/parallelforall/thinking-parallel-part-iii-tree-construction-gpu/
			uint morton3D(float3 pos)
			{
				// Quantize to the correct resolution
				pos.x = min(max(pos.x * (float) _BrickSize, 0.0f), (float) _BrickSize - 1);
				pos.y = min(max(pos.y * (float)_BrickSize, 0.0f), (float)_BrickSize - 1);
				pos.z = min(max(pos.z * (float)_BrickSize, 0.0f), (float)_BrickSize - 1);

				// Interlace the bits
				uint xx = Part1By2((uint) pos.x);
				uint yy = Part1By2((uint) pos.y);
				uint zz = Part1By2((uint) pos.z);

				return zz << 2 | yy << 1 | xx;
			}

			// Return the index into the hz-ordered array of data given a quantized point within the volume
			uint getHZIndex(uint zIndex)
			{
				uint hzIndex = (zIndex | _LastBitMask);		// set leftmost one
				hzIndex /= hzIndex & -hzIndex;				// remove trailing zeros
				return (hzIndex >> 1);						// remove rightmost one
			}

			float3 texCoord3DFromHzIndex(uint hzIndex, uint texWidth, uint texHeight, uint texDepth)
			{
				float3 texCoord = float3(0,0,0);
				texCoord.z = hzIndex / (texWidth * texHeight);
				hzIndex = hzIndex - (texCoord.z * texWidth * texHeight);
				texCoord.y = hzIndex / texWidth;
				texCoord.x = hzIndex % texHeight;

				// Convert to texture coordinates in [0, 1]
				texCoord.z = texCoord.z / (float)texDepth;
				texCoord.y = texCoord.y / (float)texHeight;
				texCoord.x = texCoord.x / (float)texWidth;

				return texCoord;
			}

			// Returns the masked z index, allowing for the the data to be quantized to a level of detail specified by the _CurrentZLevel.
			uint computeMaskedZIndex(uint zIndex)
			{
				int zBits = _MaxZLevel * 3;
				uint zMask = -1 >> (zBits - 3 * _CurrentZLevel) << (zBits - 3 * _CurrentZLevel);
				return zIndex & zMask;
			}

			/***************************************** END HZ CURVING CODE ************************************************/

			/********* SAMPLING 3D HZ CURVED RAW DATA WITH TEXTURE COORD CALCULATION **********/
			float sampleIntensityHz3D(float3 pos)
			{
				uint zIndex = morton3D(pos);										// Get the Z order index		
				uint maskedZIndex = computeMaskedZIndex(zIndex);					// Get the masked Z index
				uint hzIndex = getHZIndex(maskedZIndex);							// Find the hz order index
				uint dataCubeDimension = 1 << _CurrentZLevel;						// The dimension of the data brick using the current hz level.
				float3 texCoord = texCoord3DFromHzIndex(hzIndex, dataCubeDimension, dataCubeDimension, dataCubeDimension);
#ifdef BIT_8
				float data = tex3Dlod(_VolumeDataTexture, float4(texCoord, 0)).a;
#elif BIT_16
				float data = tex3Dlod(_VolumeDataTexture, float4(texCoord, 0)).r;
#endif

				// Slice and Threshold (from landon wooley implementation)
				// slice (eliminates data outside of the bounding box defined by _SliceAxis* variables)
				data *= step(_SliceAxisXMin, texCoord.x);
				data *= step(_SliceAxisYMin, texCoord.y);
				data *= step(_SliceAxisZMin, texCoord.z);
				data *= step(texCoord.x, _SliceAxisXMax);
				data *= step(texCoord.y, _SliceAxisYMax);
				data *= step(texCoord.z, _SliceAxisZMax);

				return data;
			}

			/********* SAMPLING 3D RAW WITH POSITION GIVEN ***********/
			float sampleIntensityRaw3D(float3 pos)
			{
#ifdef BIT_8
				return tex3Dlod(_VolumeDataTexture, float4(pos, 0)).a;
#elif BIT_16
				return tex3Dlod(_VolumeDataTexture, float4(pos, 0)).r;
#endif
			}
			
			// Gets the intensity data value at a given position in the volume.
			// Note: This is a wrapper for the other sampling methods.
			// Note: pos is normalized in [0, 1]
			float4 sampleIntensity(float3 pos) {
#ifdef USING_RAW_DATA
				float data = sampleIntensityRaw3D(pos);
#elif USING_HZ_DATA
				float data = sampleIntensityHz3D(pos);
#endif
				return float4(data, data, data, data);
			}

			/********* SAMPLING THE TRANSFER FUNCTION **********/
			float4 sampleTransferFunction(float isovalue)
			{
#ifdef BIT_8
				// Only need to sample along the x axis of the texture
				return tex2Dlod(_TransferFunctionTex, float4(isovalue, 0.0, 0.0, 0.0));
#elif BIT_16
				// TODO: Must sample in the x and y dimensions of the texture
				float sampX = isovalue / 256.0f;
				float sampY = isovalue % 256;
				return tex2Dlod(_TransferFunctionTex, float4(sampX, sampY, 0.0, 0.0));;
#endif
			}

			// fragment program
			float4 frag(v2f i) : COLOR
			{
				i.ray_d = normalize(i.ray_d);

				// calculate eye ray intersection with cube bounding box
				float3 boxMin = float3(-0.5, -0.5, -0.5);
				float3 boxMax = float3(0.5, 0.5, 0.5);
				float tNear, tFar;
				bool hit = IntersectBox(i.ray_o, i.ray_d, boxMin, boxMax, tNear, tFar);

				if (!hit) 
					discard;
				if (tNear < 0.0) 
					tNear = 0.0;

				// Calculate intersection points with the cube
				float3 pNear = i.ray_o + (i.ray_d*tNear);
				float3 pFar = i.ray_o + (i.ray_d*tFar);

				// Convert to texture space
				pNear = pNear + 0.5;
				pFar = pFar + 0.5;
				//return float4(pNear, 1);		// Test for near intersections
				//return float4(pFar , 1);		// Test for far intersections
				
				// Set up ray marching parameters
				float3 ray_start = pNear;									// The start position of the ray
				float3 ray_stop = pFar;										// The end position of the ray
				float3 ray_pos = ray_start;									// The current position of the ray during the march

				float3 ray_dir = ray_stop - ray_start;						// The direction of the ray (un-normalized)
				float ray_length = length(ray_dir);							// The length of the ray to travel
				ray_dir = normalize(ray_stop - ray_start);					// The direction of the ray (normalized)

				//float step_size = ray_length / (float)_Steps;
				//float3 ray_step = ray_dir * step_size;

				float3 ray_step = normalize(ray_dir) * sqrt(3) / _Steps;

				//return float4(abs(ray_stop - ray_start), 1);
				//return float4(ray_length, ray_length, ray_length, 1);

				// Use the clipping plane to clip the volume, if it is enabled
				if (_ClippingPlaneEnabled == 1)
				{
					// Inputs from the application
					float3 plane_norm = normalize(_ClippingPlaneNormal);		// The global normal of the clipping plane
					float3 plane_pos = _ClippingPlanePosition + 0.5; 			// The plane position in model space / texture space

					// Calculate values needed for ray-plane intersection
					float denominator = dot(plane_norm, ray_dir);
					float t = 0.0;
					if (denominator != 0.0)
					{
						t = dot(plane_norm, plane_pos - ray_start) / denominator;		// t == positive, plane is in front of eye | t == negative, plane is behind eye
					}
					
					bool planeFacesForward = denominator > 0.0;

					if ((!planeFacesForward) && (t < 0.0))
						discard;
					if ((planeFacesForward) && (t > ray_length))
						discard;
					if ((t > 0.0) && (t < ray_length))
					{
						if (planeFacesForward)
						{
							ray_start = ray_start + ray_dir * t;
						}
						else
						{
							ray_stop = ray_start + ray_dir * t;
						}
						ray_dir = ray_stop - ray_start;
						ray_pos = ray_start;
						ray_length = length(ray_dir);
						ray_dir = normalize(ray_dir);
					}
				}

				// Perform the ray march
				float4 fColor = 0;
				for (int k = 0; k < _Steps; k++)
				{
					// Determine the value at this point on the current ray
					float4 intensity = sampleIntensity(ray_pos);

					// Sample from the texture generated by the transfer function
					//float4 sampleColor = tex2Dlod(_TransferFunctionTex, float4(intensity.a, 0.0, 0.0, 0.0)); 
					float4 sampleColor = sampleTransferFunction(intensity.a);

					// Front to back blending function
					fColor.rgb = fColor.rgb + (1 - fColor.a) * sampleColor.a * sampleColor.rgb;
					fColor.a = fColor.a + (1 - fColor.a) * sampleColor.a;

					// March along the ray
					ray_pos += ray_step;
					
					// Check if we have marched out of the cube
					if (ray_pos.x < 0 || ray_pos.y < 0 || ray_pos.z < 0) break;
					if (ray_pos.x > 1 || ray_pos.y > 1 || ray_pos.z > 1) break;

					// Check if accumulated alpha is greater than 1.0
					if (fColor.a > 1.0) break;
				}

				return fColor * _NormPerRay;
			}
			ENDCG
		}
	}
	FallBack Off
}
