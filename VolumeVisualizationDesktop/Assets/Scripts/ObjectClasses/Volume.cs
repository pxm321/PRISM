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


/* Volume | Marko Sterbentz 8/2/2017 Randall Reese 09/11/2018*/

using System;
using System.IO;
using UnityEngine;
using SimpleJSON;

/// <summary>
/// This class represents the volume to be visualized.
/// </summary>
public class Volume {

	/* Member variables */
	private Brick[] bricks;
	private int bitsPerPixel;
	private int bytesPerPixel;
	private int totalBricks;
	private int minLevel;
	private int maxLevel;
    private int maxZLevel;
	private int[] globalSize;
	private string dataPath;
	private Vector3 position;
	public GameObject volumeCube;
    private string brickDataType;
	public Vector3 scale;
	public string endianness;
	private Vector3 boxMin;		// The bottom, front, left corner of the bounding box around the volume (can be different than the volume's corner)
	private Vector3 boxMax;		// The top, back, right corner of the bounding box around the volume (can be different than the volume's corner)
    public SievasController controller; 





	/* Properties */
	public Brick[] Bricks
	{
		get
		{
			return bricks;
		}
		set
		{
			bricks = value;
		}
	}
	public int BitsPerPixel
	{
		get
		{
			return bitsPerPixel;
		}
		set
		{
			bitsPerPixel = value;
		}
	}
	public int BytePerPixel
	{
		get
		{
			return bytesPerPixel;
		}
		set
		{
			bytesPerPixel = value;
		}
	}
	public int MinLevel
	{
		get
		{
			return minLevel;
		}
		set
		{
			minLevel = value;
		}
	}
	public int MaxLevel
	{
		get
		{
			return maxLevel;
		}
		set
		{
			maxLevel = value;
		}
	}

    public int MaxZLevel
    {
        get
        {
            return maxZLevel;
        }
        set
        {
            maxZLevel = value;
        }
    }
    public int[] GlobalSize
	{
		get
		{
			return globalSize;
		}
		set
		{
			globalSize = value;
		}
	}
	public string DataPath
	{
		get
		{
			return dataPath;
		}
		set
		{
			dataPath = value;
		}
	}
	public Vector3 Position
	{
		get
		{
			return position;
		}
		set
		{
			position = value;
		}
	}
	public GameObject VolumeCube
	{
		get
		{
			return volumeCube;
		}
	}
    public string BrickDataType
    {
        get
        {
            return brickDataType;
        }
        set
        {
            brickDataType = value;
        }
    }
	public Vector3 Scale
	{
		get
		{
			return volumeCube.transform.localScale;
		}
		set
		{

            volumeCube.transform.localScale = value;

        }
	}
	public string Endianness
	{
		get
		{
			return endianness;
		}
		set
		{
			endianness = value;
		}
	}
	public Vector3 BoxMin
	{
		get
		{
			return boxMin;
		}
		set
		{
			boxMin = value;
		}
	}
	public Vector3 BoxMax
	{
		get
		{
			return boxMax;
		}
		set
		{
			boxMax = value;
		}
	}

	/* Constructors */
	/// <summary>
	/// Creates a new instance of a volume.
	/// </summary>
	public Volume()
	{

	}

	/// <summary>
	/// Creates a new instance of a volume.
	/// </summary>
	/// <param name="_dataPath"></param>
	/// <param name="_metadataFileName"></param>
	/// <param name="_volumeMaterial"></param>
	public Volume(string _dataPath, string _metadataFileName)
	{
        

        // Create the (non-visible) Unity game object that will represent the volume
        volumeCube = GameObject.CreatePrimitive(PrimitiveType.Cube);
        volumeCube.name = "Volume_Cube";


        // Load the volume from the JSOn metadata file
        loadVolume(_dataPath, _metadataFileName);

        //Debug.Log("The Scale right after loading the volume is " + Scale);

        // Set the default position of the volume
        Position = Vector3.Scale(new Vector3(0.5f, 0.5f, 0.5f), this.Scale);
        

        // Set the position of the Unity game object
        volumeCube.transform.position = Position;

        // Make the Unity game object invisible
        volumeCube.GetComponent<MeshRenderer>().enabled = false;


        BoxMin = new Vector3(0.0f, 0.0f, 0.0f);

        
        BoxMax = Scale;
    }

	/* Methods */
	/// <summary>
	/// Loads the volume data in the given directory.
	/// </summary>
	/// <param name="_dataPath"></param>
	/// <param name="metadataFileName"></param>
	public void loadVolume(string _dataPath, string metadataFileName)
	{
		try
		{
			// Set the datapath
			DataPath = _dataPath;

			// Read the JSON file specified by the path
			StreamReader reader = new StreamReader(dataPath + metadataFileName);
			string textFromFile = reader.ReadToEnd();
			reader.Close();

			// Create a dictionary to store the values of the JSON file
			JSONNode N = JSON.Parse(textFromFile);

			// Assign the data from the file to the member variables of VolumeController
			minLevel = N["minLevel"].AsInt;
			maxLevel = N["maxLevel"].AsInt;
			totalBricks = N["totalBricks"].AsInt;
			bytesPerPixel = N["bytesPerPixel"].AsInt;
			bitsPerPixel = bytesPerPixel * 8;
			globalSize = new int[]{  N["globalSize"][0].AsInt,
									 N["globalSize"][1].AsInt,
									 N["globalSize"][2].AsInt };
			bricks = new Brick[totalBricks];

			// Read in the endianness of the bytes (this is mainly relevant for 16-bit data)
			endianness = N["endianness"];

			// Get the file types being read in and ensure the correct type of sampling is done in the shader
			brickDataType = Path.GetExtension(N["bricks"][0]["filename"]);
			Debug.Log("Volume detected as \"" + brickDataType + "\" type.");



            // Transform the volume after the bricks have been created. 
            //Unity seems to ignore all requests to scale the bricks or the volume. 
            float[] read_in_scale = new float[]{
                                                 N["scale"][0].AsFloat,
                                                 N["scale"][1].AsFloat,
                                                 N["scale"][2].AsFloat
                                               };
            float invertedMinScale = 1.0f / Mathf.Min(read_in_scale); 
        
            this.Scale = Vector3.Scale(new Vector3(read_in_scale[0], read_in_scale[1], read_in_scale[2]),  new Vector3(invertedMinScale, invertedMinScale, invertedMinScale));
            
            // Generate boundingVolumeCorner and boundingVolumeCenter (IN WORLD SPACE)

            float maxGlobalSize = Mathf.Max(globalSize);
            





            
            Vector3 boundingVolumeCenter = Vector3.Scale(new Vector3(maxGlobalSize, maxGlobalSize, maxGlobalSize), this.Scale) / 2.0f;
            Vector3 boundingVolumeCorner = new Vector3(0, 0, 0);
            Vector3 b = boundingVolumeCenter - boundingVolumeCorner;

            // Find volumeCenter and volumeCorner of the data (IN WORLD SPACE)
            Vector3 volumeCenter = Vector3.Scale(new Vector3(globalSize[0], globalSize[1], globalSize[2]), this.Scale)/ 2.0f;
            Vector3 volumeCorner = new Vector3(0,0,0);
            Vector3 c = volumeCenter - volumeCorner;

            // Calculate vector a: the bottom left corner of the volume (IN VOXEL SPACE)
           
            Vector3 volumeCornerVoxelSpace = b - c;

            // Create and position all of the bricks within a 1 x 1 x 1 cube
            for (int i = 0; i < bricks.Length; i++)
			{
				// Read in metadata from the file
				string newBrickFilename = DataPath + N["bricks"][i]["filename"];
				int newBrickSize = N["bricks"][i]["size"];
				Vector3 newBrickPosition = Vector3.Scale(new Vector3(N["bricks"][i]["position"][0].AsInt,
													   N["bricks"][i]["position"][1].AsInt,
													   N["bricks"][i]["position"][2].AsInt), this.Scale);

                                                       
                
                // Calculate the position for each brick (IN VOXEL SPACE)
                Vector3 brickPositionVoxelSpace = volumeCornerVoxelSpace + newBrickPosition;
                

                // Calculate the brick offset (IN VOXEL SPACE)
                Vector3 brickOffsetVoxelSpace = Vector3.Scale(new Vector3(newBrickSize, newBrickSize, newBrickSize), this.Scale) / 2.0f;
               
                // Calculate final position for the brick (IN WORLD SPACE)
                Vector3 finalBrickPosition = (brickPositionVoxelSpace + brickOffsetVoxelSpace) / maxGlobalSize;

                // Calculate the bottom, front, left corner of the brick (IN WORLD SPACE)
                Vector3 brickMin = finalBrickPosition - ((Vector3.Scale(new Vector3(newBrickSize, newBrickSize, newBrickSize) , this.Scale)/ 2.0f) / maxGlobalSize) ;
                
                // Calculate the top, back, right corner of the brick (IN WORLD SPACE) 
                Vector3 brickMax = finalBrickPosition + ((Vector3.Scale(new Vector3(newBrickSize, newBrickSize, newBrickSize), this.Scale) / 2.0f) / maxGlobalSize) ;
               
                // Create the brick
                bricks[i] = new Brick(newBrickFilename, newBrickSize, finalBrickPosition, brickMin, brickMax, this);

                // Scale the bricks to the correct size
                bricks[i].GameObject.transform.localScale = new Vector3(bricks[i].Size, bricks[i].Size, bricks[i].Size) / maxGlobalSize;
                
            }


            MaxZLevel = calculateMaxZlevel();

			Debug.Log("Metadata read. SCALE " + Scale.ToString("G4"));
		}
		catch (Exception e)
		{
			Debug.Log("Failed to read the metadata file: " + e);
		}
	}

    private int calculateMaxZlevel()
    {
        int[] zLevs = new int[totalBricks];

        for(int b = 0; b < totalBricks; b++)
        {
            zLevs[b] = Bricks[b].MaxZLevel;
        }

        return Mathf.Max(zLevs);
    }

	/// <summary>
	/// Generates the isovalue range given the number of bits per pixels.
	/// </summary>
	/// <returns></returns>
	public int calculateIsovalueRange()
	{
		return ((int)Mathf.Pow(2.0f, bitsPerPixel)) - 1;
	}

	/// <summary>
	/// Returns a struct containing information about this volume to be passed to the compute shader.
	/// </summary>
	/// <returns></returns>
	public MetaVolume getMetaVolume()//The MetaVolume struct is defined in RenderingShader.compute
	{
		MetaVolume mv;
		mv.position = Position;
		mv.boxMin = BoxMin;
		mv.boxMax = BoxMax;
		mv.scale = this.Scale;
		mv.numBricks = totalBricks;
		mv.isHz = BrickDataType == ".hz" ? 1 : 0;
		mv.numBits = BitsPerPixel;
		mv.maxGlobalSize = Mathf.Max(GlobalSize);
		return mv;
	}
}
