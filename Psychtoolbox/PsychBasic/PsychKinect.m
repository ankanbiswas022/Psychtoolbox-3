function varargout = PsychKinect(varargin)
% PsychKinect -- Control and access the Microsoft XBOX360-Kinect.
% 
%
% [tex, gltexid, gltextarget] = PsychKinect('CreateImageTexture', windowPtr, kinectPtr [, oldtex]);
% - Convert current RGB video camera image from Kinect 'kinectPtr'
% into a PTB texture for window 'windowPtr'. Return PTB texture handle
% 'tex', and OpenGL texture handle 'gltexid' and texture target 'gltextarget'.
%
% Optionally takes PTB texture handle 'oldtex' of a previously created
% texture and reuses that textures storage for the new data for higher
% efficiency.
%

% History:
%  5.12.2010  mk   Initial version written.
global GL;

persistent kinect_opmode;
persistent glsl;

kinect_opmode = 3;

% Command specified? Otherwise we output the help text of us and
% the low level driver:
if nargin > 0
	cmd = varargin{1};
else
	help PsychKinect;
	PsychKinectCore;
	return;
end

if strcmpi(cmd, 'CreateObject')

	if nargin < 2 || isempty(varargin{2})
		error('You must provide a valid "window" handle as 1st argument!');
	end
	win = varargin{2};

	if nargin < 3 || isempty(varargin{3})
		error('You must provide a valid "kinect" handle as 2nd argument!');
	end
	kinect = varargin{3};

	if nargin < 4 || isempty(varargin{4})
		kmesh.tex = [];
		kmesh.vbo = [];
		kmesh.buffersize = 0;
	else
		kmesh = varargin{4};
	end

	kmesh.xyz = [];
	kmesh.rgb = [];

	% Turn RGB video camera image into a Psychtoolbox texture and corresponding
	% OpenGL rectangle texture:
	[imbuff, width, height, channels] = PsychKinectCore('GetImage', kinect, 0, 1);
	if width > 0 && height > 0
		kmesh.tex = Screen('SetOpenGLTextureFromMemPointer', win, kmesh.tex, imbuff, width, height, channels, 1, GL.TEXTURE_RECTANGLE_EXT);
		[ gltexid gltextarget ] =Screen('GetOpenGLTexture', win, kmesh.tex);
		kmesh.gltexid = gltexid;
		kmesh.gltextarget = gltextarget;
	else
		varargout{1} = [];
		printf('PsychKinect: WARNING: Failed to fetch RGB image data!\n');
		return;
	end

	if kinect_opmode == 0
		% Dumb mode: Return a complete matrix with encoded vertex positions
		% and vertex colors:
		[foo, width, height, channels, glformat] = PsychKinect('GetDepthImage', kinect, 2, 0);
		foo = reshape (foo, 6, size(foo,2) * size(foo,3));
		kmesh.xyz = foo(1:3, :);
		kmesh.rgb = foo(4:6, :);
		kmesh.type = 0;
		kmesh.glformat = glformat;
	end

	if kinect_opmode == 1
		% Fetch databuffer with preformatted data for a VBO that
		% contains interleaved (vx,vy,vz) 3D vertex positions and (tx,ty)
		% 2D texture coordinates, i.e., (vx,vy,vz,tx,ty) per element:
		[vbobuffer, width, height, channels, glformat] = PsychKinect('GetDepthImage', kinect, 3, 0);
		if width > 0 && height > 0
			Screen('BeginOpenGL', win);
			if isempty(kmesh.vbo)
				kmesh.vbo = glGenBuffers(1);
			end
			glBindBuffer(GL.ARRAY_BUFFER, kmesh.vbo);
			kmesh.buffersize = width * height * channels * 8;
			glBufferData(GL.ARRAY_BUFFER, kmesh.buffersize, vbobuffer, GL.STREAM_DRAW);
			glBindBuffer(GL.ARRAY_BUFFER, 0);
			Screen('EndOpenGL', win);
			kmesh.Stride = channels * 8;
			kmesh.textureOffset = 3 * 8;
			kmesh.nrVertices = width * height;
			kmesh.type = 1;
			kmesh.glformat = glformat;
		else
			varargout{1} = [];
			printf('PsychKinect: WARNING: Failed to fetch VBO geometry data!\n');
			return;
		end
	end

	if kinect_opmode == 2 || kinect_opmode == 3
		if isempty(glsl)
			% First time init of shader:
			fx_d = 5.9421434211923247e+02;
			fy_d = 5.9104053696870778e+02;
			cx_d = 3.3930780975300314e+02;
			cy_d = 2.4273913761751615e+02;

			fx_rgb = 5.2921508098293293e+02;
			fy_rgb = 5.2556393630057437e+02;
			cx_rgb = 3.2894272028759258e+02;
			cy_rgb = 2.6748068171871557e+02;

			R = [[ 9.9984628826577793e-01, 1.2635359098409581e-03, -1.7487233004436643e-02  ]; ...
			     [ -1.4779096108364480e-03, 9.9992385683542895e-01, -1.2251380107679535e-02 ]; ...
			     [ 1.7470421412464927e-02, 1.2275341476520762e-02,  9.9977202419716948e-01  ]];

			T = [ 1.9985242312092553e-02, -7.4423738761617583e-04, -1.0916736334336222e-02 ];

			if kinect_opmode == 2
				glsl = LoadGLSLProgramFromFiles('KinectShaderStandard');
			else
				glsl = LoadGLSLProgramFromFiles('KinectShaderCompressed');
			end

			glUseProgram(glsl);
			glUniform4f(glGetUniformLocation(glsl, 'depth_intrinsic'), fx_d, fy_d, cx_d, cy_d);
			glUniform4f(glGetUniformLocation(glsl, 'rgb_intrinsic'), fx_rgb, fy_rgb, cx_rgb, cy_rgb);
			glUniformMatrix3fv(glGetUniformLocation(glsl, 'R'), 1, GL.FALSE, R);
			glUniform3fv(glGetUniformLocation(glsl, 'T'), 1, T);
			glUseProgram(0);
			repeatedscan = 0;
		else
			repeatedscan = 1;
		end

		% Fetch databuffer with preformatted data for a VBO that
		% contains interleaved (x,y,vz) 3D vertex positions:
		if kinect_opmode == 2
			format = 4 + repeatedscan;
		else
			format = 6; % + repeatedscan;
		end
		[vbobuffer, width, height, channels, glformat] = PsychKinect('GetDepthImage', kinect, format, 0);
		if width > 0 && height > 0
			Screen('BeginOpenGL', win);
			if isempty(kmesh.vbo)
				kmesh.vbo = glGenBuffers(1);
			end
			glBindBuffer(GL.ARRAY_BUFFER, kmesh.vbo);
			kmesh.buffersize = width * height * channels * 8;
			glBufferData(GL.ARRAY_BUFFER, kmesh.buffersize, vbobuffer, GL.STREAM_DRAW);
			glBindBuffer(GL.ARRAY_BUFFER, 0);
			Screen('EndOpenGL', win);
			kmesh.Stride = channels * 8;
			kmesh.textureOffset = 0;
			kmesh.nrVertices = width * height;
			kmesh.type = kinect_opmode;
			kmesh.glsl = glsl;
			kmesh.glformat = glformat;
		else
			varargout{1} = [];
			printf('PsychKinect: WARNING: Failed to fetch VBO geometry data!\n');
			return;
		end
	end

	% Store handle to kinect:
	kmesh.kinect = kinect;

	varargout{1} = kmesh;

	return;
end

if strcmpi(cmd, 'DeleteObject')
	if nargin < 2 || isempty(varargin{2})
		error('You must provide a valid "window" handle as 1st argument!');
	end
	win = varargin{2};

	if nargin < 3 || isempty(varargin{3})
		error('You must provide a valid "mesh" struct as 2nd argument!');
	end
	kmesh = varargin{3};
	
	if ~isempty(kmesh.tex)
		Screen('Close', kmesh.tex);
	end

	if kmesh.type == 0
		return;
	end

	if kmesh.type == 1 || kmesh.type == 2 || kmesh.type == 3
		if ~isempty(kmesh.vbo)
			glDeleteBuffers(1, kmesh.vbo);
		end
		return;
	end

	return;
end

if strcmpi(cmd, 'RenderObject')

	if nargin < 2 || isempty(varargin{2})
		error('You must provide a valid "window" handle as 1st argument!');
	end
	win = varargin{2};

	if nargin < 3 || isempty(varargin{3})
		error('You must provide a valid "mesh" struct as 2nd argument!');
	end
	kmesh = varargin{3};

	if nargin < 4 || isempty(varargin{4})
		drawtype = 0;
	else
		drawtype = varargin{4};
	end

	% Primitive way: All data encoded inside kmesh.xyz, kmesh.rgb as
	% double matrices. Use PTB function to draw it. Sloooow:
	if kmesh.type == 0
		moglDrawDots3D(win, kmesh.xyz, 2, kmesh.rgb, [], 1);
	end

	% VBO with encoded texture coordinates?
	if kmesh.type == 1
		% Yes. No need for GPU post-processing, just bind & draw:

		% Activate and bind texture on unit 0:
		glActiveTexture(GL.TEXTURE0);
		glEnable(kmesh.gltextarget);
		glBindTexture(kmesh.gltextarget, kmesh.gltexid);

		% Activate and bind VBO:
		glEnableClientState(GL.VERTEX_ARRAY);
	        glBindBuffer(GL.ARRAY_BUFFER, kmesh.vbo);
	        glVertexPointer(3, GL.DOUBLE, kmesh.Stride, 0);
		glEnableClientState(GL.TEXTURE_COORD_ARRAY);
		glTexCoordPointer(2, GL.DOUBLE, kmesh.Stride, kmesh.textureOffset);

		% Pure point cloud rendering requested?
		if drawtype == 0
			glDrawArrays(GL.POINTS, 0, kmesh.nrVertices);
		end
		
	        glBindBuffer(GL.ARRAY_BUFFER, 0);
		glDisableClientState(GL.VERTEX_ARRAY);
		glDisableClientState(GL.TEXTURE_COORD_ARRAY);
		glBindTexture(kmesh.gltextarget, 0);
		glDisable(kmesh.gltextarget);
	end

	if kmesh.type == 2 || kmesh.type == 3
		% Yes. Need for GPU post-processing:

		% Activate and bind texture on unit 0:
		glActiveTexture(GL.TEXTURE0);
		glEnable(kmesh.gltextarget);
		glBindTexture(kmesh.gltextarget, kmesh.gltexid);

		% Activate and bind VBO:
		glEnableClientState(GL.VERTEX_ARRAY);
	        glBindBuffer(GL.ARRAY_BUFFER, kmesh.vbo);
		if kmesh.type == 3
	        	glVertexPointer(2, kmesh.glformat, kmesh.Stride, 0);
		else
	        	glVertexPointer(3, kmesh.glformat, kmesh.Stride, 0);
		end
		glUseProgram(kmesh.glsl);

		% Pure point cloud rendering requested?
		if drawtype == 0
			glDrawArrays(GL.POINTS, 0, kmesh.nrVertices);
		end
		
		glUseProgram(0);
	        glBindBuffer(GL.ARRAY_BUFFER, 0);
		glDisableClientState(GL.VERTEX_ARRAY);
		glBindTexture(kmesh.gltextarget, 0);
		glDisable(kmesh.gltextarget);
	end

	return;
end

% No matching command found: Pass all arguments to the low-level
% PsychKinectCore mex file driver. Low level command might be
% implemented there:
[ varargout{1:nargout} ] = PsychKinectCore(varargin{:});

return;
