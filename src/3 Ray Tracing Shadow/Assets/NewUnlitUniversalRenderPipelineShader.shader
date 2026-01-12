Shader "Custom/NewUnlitUniversalRenderPipelineShader"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white"
    }

    SubShader
    {
        Tags { "LightMode" = "NewURPRenderFeaturePass" }
        // Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            Name "NewURPRenderFeaturePass"

            HLSLPROGRAM

            // #pragma vertex vert
            // #pragma fragment frag
            #pragma raytracing surface_shader

            // #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "UnityRaytracingMeshUtils.cginc"

            // struct Attributes
            // {
            //     float4 positionOS : POSITION;
            //     float2 uv : TEXCOORD0;
            // };

            // struct Varyings
            // {
            //     float4 positionHCS : SV_POSITION;
            //     float2 uv : TEXCOORD0;
            // };

            // TEXTURE2D(_BaseMap);
            // SAMPLER(sampler_BaseMap);

            // CBUFFER_START(UnityPerMaterial)
            //     half4 _BaseColor;
            //     float4 _BaseMap_ST;
            // CBUFFER_END

            // Varyings vert(Attributes IN)
            // {
            //     Varyings OUT;
            //     OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
            //     OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
            //     return OUT;
            // }

            // half4 frag(Varyings IN) : SV_Target
            // {
            //     half4 color = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;
            //     return color;
            // }

            struct RayPayload
            {
                bool hit;
                float3 radiance;
            };

            struct AtrributeData
            {
                float2 barycentrics;
            };

            RaytracingAccelerationStructure SceneAS;

            struct Vertex
            {
                float3 position;
                float3 normal;
                float4 tangent;
                float2 texCoord0;
                float2 texCoord1;
                float2 texCoord2;
                float2 texCoord3;
                float4 color;
            };

            Vertex FetchVertex(uint vertexIndex)
            {
                Vertex v;
                v.position = UnityRayTracingFetchVertexAttribute3(vertexIndex, kVertexAttributePosition);
                v.normal = UnityRayTracingFetchVertexAttribute3(vertexIndex, kVertexAttributeNormal);
                v.tangent = UnityRayTracingFetchVertexAttribute4(vertexIndex, kVertexAttributeTangent);
                v.texCoord0 = UnityRayTracingFetchVertexAttribute2(vertexIndex, kVertexAttributeTexCoord0);
                v.texCoord1 = UnityRayTracingFetchVertexAttribute2(vertexIndex, kVertexAttributeTexCoord1);
                v.texCoord2 = UnityRayTracingFetchVertexAttribute2(vertexIndex, kVertexAttributeTexCoord2);
                v.texCoord3 = UnityRayTracingFetchVertexAttribute2(vertexIndex, kVertexAttributeTexCoord3);
                v.color = UnityRayTracingFetchVertexAttribute4(vertexIndex, kVertexAttributeColor);
                return v;
            }

            float2 barycentricInterpolate2 (float2 v0, float2 v1,float2 v2, float3 barycentrics)
            {
                return v0 * barycentrics.x + v1 * barycentrics.y + v2 * barycentrics.z;
            }

            float3 barycentricInterpolate3(float3 v0, float3 v1, float3 v2, float3 barycentrics)
            {
                return v0 * barycentrics.x + v1 * barycentrics.y + v2 * barycentrics.z;
            }

            float4 barycentricInterpolate4(float4 v0, float4 v1, float4 v2, float3 barycentrics)
            {
                return v0 * barycentrics.x + v1 * barycentrics.y + v2 * barycentrics.z;
            }

            Vertex InterpolateVertices(Vertex v0, Vertex v1, Vertex v2, float3 barycentrics)
            {
                Vertex v;
                v.position = barycentricInterpolate3(v0.position, v1.position, v2.position, barycentrics);
                v.normal = barycentricInterpolate3(v0.normal, v1.normal, v2.normal, barycentrics);
                v.tangent = barycentricInterpolate4(v0.tangent, v1.tangent, v2.tangent, barycentrics);
                v.texCoord0 = barycentricInterpolate2(v0.texCoord0, v1.texCoord0, v2.texCoord0, barycentrics);
                v.texCoord1 = barycentricInterpolate2(v0.texCoord1, v1.texCoord1, v2.texCoord1, barycentrics);
                v.texCoord2 = barycentricInterpolate2(v0.texCoord2, v1.texCoord2, v2.texCoord2, barycentrics);
                v.texCoord3 = barycentricInterpolate2(v0.texCoord3, v1.texCoord3, v2.texCoord3, barycentrics);
                v.color = barycentricInterpolate4(v0.color, v1.color, v2.color, barycentrics);
                return v;
            }
            
            struct ShadowPayload
            {
                bool hit;
            };

            bool TraceShadow(float3 lightDirection, float3 normal, float3 position)
            {
                RayDesc ray;
                ray.Origin = position + 1e-6 * normal;
                ray.Direction = lightDirection;
                ray.TMin = 1e-6;
                ray.TMax = 1e5;

                ShadowPayload payload = (ShadowPayload)0;
                payload.hit = true;
                TraceRay(SceneAS, RAY_FLAG_SKIP_CLOSEST_HIT_SHADER | RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH,
                    0xFF, 0, 1, 1, ray, payload);
                    return payload.hit;
            }

            [shader("closesthit")]
            void ClosestHitMain(inout RayPayload payload : SV_RayPayload, AtrributeData attribs : SV_IntersectionAttributes)
            {
                uint3 triangleIndices = UnityRayTracingFetchTriangleIndices(PrimitiveIndex());

                Vertex v0,v1,v2;
                v0 = FetchVertex(triangleIndices.x);
                v1 = FetchVertex(triangleIndices.y);
                v2 = FetchVertex(triangleIndices.z);

                float3 barycentricCoords = float3(
                    1.0 - attribs.barycentrics.x - attribs.barycentrics.y,
                    attribs.barycentrics.x,
                    attribs.barycentrics.y
                );
                Vertex v = InterpolateVertices(v0,v1,v2,barycentricCoords);

                float3 color = _BaseColor.rgb * SAMPLE_TEXTURE2D_LOD(_BaseMap, sampler_BaseMap, v.texCoord0, 0).rgb;
                float3 normal = TransformObjectToWorldNormal(v.normal);
                
                float3 position = TransformObjectToWorld(v.position);
                bool is_shadow = TraceShadow(_MainLightPosition, normal, position);
                float shade = is_shadow? 0.1 :
                    lerp(0.1, 1.0, max(0, dot(normal, _MainLightPosition)));
                color = _MainLightColor * color * shade;

                payload.hit = true;
                payload.radiance = color;
            }

            ENDHLSL
        }
    }
}
