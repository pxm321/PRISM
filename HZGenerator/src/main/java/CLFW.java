/**
 * Nate VM.
 * The following class contains static methods for OpenCL use.
 * Initialize before use.
 */

import static java.lang.Math.*;
import static org.jocl.CL.*;
import org.jocl.*;

import java.io.File;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.HashMap;
import java.util.Scanner;

import org.json.*;


public class CLFW {
	public static HashMap<String, cl_kernel> Kernels;
	public static cl_platform_id DefaultPlatform;
	public static cl_device_id DefaultDevice;
	public static cl_command_queue DefaultQueue;
	public static cl_context DefaultContext;

	//Prevent direct instantiation
	protected CLFW() {}

	// Generates the static fields required to use OpenCL
	public static int Initialize(File openCLSettings) {
		int[] error = new int[1];
		final int platformIndex = 0;
		final long deviceType = CL_DEVICE_TYPE_ALL;
		final int deviceIndex = 0;

		// Obtain the number of platforms
		int numPlatformsArray[] = new int[1];
		error[0] |= clGetPlatformIDs(0, null, numPlatformsArray);
		int numPlatforms = numPlatformsArray[0];

		// Obtain a platform ID
		cl_platform_id platforms[] = new cl_platform_id[numPlatforms];
		error[0] |= clGetPlatformIDs(platforms.length, platforms, null);
		DefaultPlatform = platforms[platformIndex];

		// Initialize the context properties
		cl_context_properties contextProperties = new cl_context_properties();
		contextProperties.addProperty(CL_CONTEXT_PLATFORM, DefaultPlatform);

		// Obtain the number of dxevices for the platform
		int numDevicesArray[] = new int[1];
		error[0] |= clGetDeviceIDs(DefaultPlatform, deviceType, 0, null, numDevicesArray);
		int numDevices = numDevicesArray[0];

		// Obtain a device ID
		cl_device_id devices[] = new cl_device_id[numDevices];
		error[0] |= clGetDeviceIDs(DefaultPlatform, deviceType, numDevices, devices, null);
		DefaultDevice = devices[deviceIndex];

		// Create a context for the selected device
		DefaultContext = clCreateContext(
				contextProperties, 1, new cl_device_id[]{DefaultDevice},
				null, null, error);

		// Create a command queue for the selected device
			// note, depreciated. When NVidia goes to OpenCL 2.0, this should be updated
			// to clCreateCommandQueueWithProperties
		DefaultQueue =
				clCreateCommandQueue(DefaultContext, DefaultDevice, 0, error);

		// Compile source files
		try {
			// Read json to get kernel file names
			String contents = new String(Files.readAllBytes(Paths.get(openCLSettings.getPath())));
			JSONObject obj = new JSONObject(contents);
			JSONArray arr = obj.getJSONArray("Sources");
			String[] sources = new String[arr.length()];
			for (int i = 0; i < arr.length(); ++i)
				sources[i] = new String(Files.readAllBytes(Paths.get( openCLSettings.getParent() + "/" + (String)arr.get(i))));

			// Compile the kernels
			cl_program program = clCreateProgramWithSource(DefaultContext, sources.length, sources,
					null, error);
			String compileOptions = obj.getString("CompileOptions");
			clBuildProgram(program, 0, null, compileOptions, null, null);

			// Print out potential build errors
			long logSize[] = new long[1];
			clGetProgramBuildInfo(program, DefaultDevice, CL_PROGRAM_BUILD_LOG, 0, null, logSize);
			byte logData[] = new byte[(int)logSize[0]];
			clGetProgramBuildInfo(program, DefaultDevice, CL_PROGRAM_BUILD_LOG, logSize[0],
					Pointer.to(logData), null);
			System.out.println(new String(logData, 0, logData.length - 1));

			// Generate kernel references
			int[] num_kernels_ret = new int[1];
			error[0] |= clCreateKernelsInProgram(program, 0, null, num_kernels_ret);
			cl_kernel[] temp = new cl_kernel[num_kernels_ret[0]];
			error[0] |= clCreateKernelsInProgram(program, num_kernels_ret[0], temp, null);

			Kernels = new HashMap<>();
			for (cl_kernel k : temp) {
				long[] param_value_size_ret = new long[1];
				error[0] |= clGetKernelInfo(k, CL_KERNEL_FUNCTION_NAME, 0, null, param_value_size_ret);
				byte nameData[] = new byte[(int)param_value_size_ret[0]];
				error[0] |= clGetKernelInfo(k, CL_KERNEL_FUNCTION_NAME, param_value_size_ret[0],
						Pointer.to(nameData), null);
				Kernels.put(new String(nameData, 0, nameData.length - 1), k);
			}

		} catch (Exception e) {
			System.out.println("Invalid OpenCLSettings.json file");
			e.printStackTrace();
		}


		return error[0];
	}

	public static int NextPow2(int num) {return max((int)pow(2, ceil(log(num)/log(2))), 8);}
}
