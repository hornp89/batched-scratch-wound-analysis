/*
 * Macro template to process multiple images in a folder
 */
//Creates an GUI input for choosing input and output directories, file suffix and 
//whether batch-processing mode should be used
#@ File (label = "Input directory", style = "directory") input
#@ File (label = "Output directory", style = "directory") output
#@ String(value="This macro will save processed images and a results file in csv format into the specified output directory.", visibility="MESSAGE") output_info1;
#@ String(value="When choosing 'Subfolder' in the following dialog, the folder structure of the input directory will be mirrored in the output.", visibility="MESSAGE") output_info2;
#@ String (label = "File suffix", value = ".jpg") suffix
#@ Boolean (label = "Do not show images", value = "TRUE") batch
#@ String(value="Untick this box when you want to see the processed images", visibility="MESSAGE") batch_hint;


	mode = newArray("Folder", "Subfolder");
{	Dialog.create("Choose running mode");
 	Dialog.addMessage("Choose the mode for running scratch-wound analysis");
 	Dialog.addChoice("Mode", mode, "Subfolder");
 	Dialog.addMessage("'Folder' scans for images only in the specifically selected folder but not in any subdirectories.");
 	Dialog.addMessage("'Subfolder' scans for images in all subdirectories of the specified folder but not in the folder itself.");
 	Dialog.show();

 	mode = Dialog.getChoice();
}

//Pre-set of variables. So far, these parameters have worked reasonably well for pictures taken by the CelliQ (1x1 grid).
var filter_radius = 30; //filter radius for variance filtering
var threshold = 10;	//threshold on variance filtered image
var sat_pix = 0.001; //fraction of saturated pixels in image
var min_area = 10; //minimum area in px^2 that gets detected
var fract_area = 0.3; //area fraction of largest area
var number_areas = 2; //number of areas above fract_area*max_area that gets measured
var scale = 0.7; //scale in µm/pixel

//Creates a GUI to input/change parameters
{   Dialog.create("Wound healing size options");
    Dialog.addNumber("Variance window radius", filter_radius);
    Dialog.addSlider("Threshold value", 0, 255,  threshold);
    Dialog.addNumber("Fraction of saturated pixels", sat_pix);
    Dialog.addCheckbox("Gaussion blur", true);
	Dialog.addNumber("Minimal area size", min_area); 
	Dialog.addNumber("Fraction of largest area to be detected", fract_area);
	Dialog.addNumber("Max number of areas to be measured", number_areas); 
	Dialog.addNumber("Scale in µm/pixel", scale);
    Dialog.show();
    
    filter_radius = Dialog.getNumber();
    threshold = Dialog.getNumber();
    sat_pix = Dialog.getNumber();
    gauss_blur = Dialog.getCheckbox();
    min_area = Dialog.getNumber();
    fract_area = Dialog.getNumber();
    number_areas = Dialog.getNumber();
    scale = Dialog.getNumber();
}

if (gauss_blur == true){
	Dialog.create("Gaussian blur options");
	Dialog.addNumber("Radius [pixels]", 5);
	Dialog.show();

	gauss_rad = Dialog.getNumber();
}

setBatchMode(batch);

if (mode == "Subfolder"){
processSubFolder(input);

saveAs("Results", output+"/Results.csv");

// function to scan input folder to find files with correct suffix. 
	//This will not search or process files in subdirectories.
function processSubFolder(input) {
	list = getFileList(input);
	list = Array.sort(list);
	run("Clear Results");
	for (i = 0; i < list.length; i++) {
		if(File.isDirectory(input + File.separator + list[i]))
			File.makeDirectory(output + File.separator + list[i]);
			folder = list[i];
			list_2 = getFileList(input + File.separator + list[i]);
			list_2 = Array.sort(list_2);
			for (j = 0; j < list_2.length; j++){
				if(endsWith(list_2[j], suffix))
				processFile(input+"/"+folder, output+"/"+folder, list_2[j]);
				updateResults();
			}
	}
}
}

if (mode == "Folder"){
	processFolder(input);

saveAs("Results", output+"/Results.csv");

// function to scan input folder to find files with correct suffix. 
	//This will not search or process files in subdirectories.
function processFolder(input) {
	list = getFileList(input);
	run("Clear Results");
	for (i = 0; i < list.length; i++) {
		if(endsWith(list[i], suffix))
			processFile(input, output, list[i]);
			updateResults();
	}
}
}

function processFile(input, output, file) {

open(input+"/"+file);

{
run("Select None");
snapshot();
setupUndo(); 
run("Options...", " black");
run("Duplicate...", "duplicate");
setForegroundColor(0, 0, 0);
setBackgroundColor(255, 255, 255);
roiManager("reset");
roiManager("Associate", "true");
if (gauss_blur == true){
run("Gaussian Blur...", "sigma="+gauss_rad);
}
run("8-bit");
 
if (isOpen("ROI Manager")) 
{
	selectWindow("ROI Manager");
	run("Select None");
	run("Close");
	}

run("Set Scale...", "distance=1 known="+scale+" unit=µm global");
getPixelSize(unit, pw, ph);

run("Enhance Contrast...", "saturated="+sat_pix+" normalize");
run("Variance...", "radius="+filter_radius+" stack"); 
setThreshold(0, threshold);
run("Convert to Mask", "black");
run("Fill Holes");
run("Select All");
   
run("Analyze Particles...", "size="+min_area+"-Infinity circularity=0.00-1.00 show=Nothing add stack");
run("Revert");
close();
 
roiManager("Show None");

if (roiManager("count")>=1)
{
	if (roiManager("count")>1)
	{
		area_large = newArray(roiManager("count"));
		for (i = 0; i<(roiManager("count")); i++)
		{
			roiManager("select", i)
			getStatistics(area_large[i], mean, min, max, std, histogram);
			}
			
		largest = 0;
		for (i = 0; i<(roiManager("count")); i++)
		{
			if (area_large[i]>largest)
			{
				largest = area_large[i];
				large = i;
				}
				}
       cut_off = largest*fract_area;

    	selectAreas = newArray(0);
    	selectROIs = newArray(0);
    	for (i = 0; i<(roiManager("count")); i++)
    	if (area_large[i] > cut_off)
    	{
    		selectAreas = Array.concat(selectAreas, area_large[i]);
    		selectROIs = Array.concat(selectROIs, i);
    		}

		//this set of operations sorts the ROIs according to size and selects only the top n ones
		Array.sort(selectAreas, selectROIs);
		Array.reverse(selectAreas);
		Array.reverse(selectROIs);
		selectAreas = Array.trim(selectAreas, number_areas);
		selectROIs = Array.trim(selectROIs, number_areas);
   
		if (selectROIs.length > 1)
		{
			roiManager("select", selectROIs);
			roiManager("Combine");
			}

   			else
   			{
   				roiManager("select", large);
   				}
		}

	else if (roiManager("count")==1)
	{
		roiManager("select", 0);
		}
   
	reset();
	setupUndo();
	roiManager("Set Color", "cyan");
	   
   	Roi.getContainedPoints(xpoints, ypoints);
   
  	run("Set Measurements...", "redirect=None decimal=3");
  	getStatistics(area, mean, min, max, std, histogram);
  	height_total=getHeight()*pw;
  	width_total=getWidth()*pw;
  	total_area=(height_total*width_total);
  	area_fraction=(area/total_area)*100;
  	avg_width = (area/height_total);

  	n1=getValue("results.count");
   	title_image=getTitle();
   	folder = File.getName(input);
   	setResult("Folder", n1, folder);
   	setResult("File", n1, title_image);
   	setResult("Area "+unit+"^2", n1, area);
   	setResult("Area %", n1, area_fraction);
   	setResult("Width "+unit, n1, avg_width);
   	setTool("rectangle");
  
	//Add an outline to the image that gets saved in the output directory
   	setForegroundColor(255, 255, 255);
	run("Line Width...", "line=5");
	run("Draw", "slice");
	run("Select None");
	run("Scale...", "x=0.25 y=0.25 width=348 height=260 interpolation=Bilinear average create");
	save(output+"/"+file);
	close();
	}
else 
{
	n1=getValue("results.count");
   	title_image=getTitle();
   	folder = File.getName(input);
   	setResult("Folder", n1, folder);
   	setResult("File", n1, title_image);
   	setResult("Area "+unit+"^2", n1, 0);
   	setResult("Area %", n1, 0);
   	setResult("Width "+unit, n1, 0);
   	setTool("rectangle");
   	run("Select None");
   	run("Scale...", "x=0.25 y=0.25 width=348 height=260 interpolation=Bilinear average create");
	save(output+"/"+file);
	close();
   	}
}
}