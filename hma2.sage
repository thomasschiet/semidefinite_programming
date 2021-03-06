"""Sage file for Homework Assignment 2, SDP 2018, Mastermath.

Your program should be written in this file. You may write as many
functions as you like, but you should follow the instructions in the
PDF file. The functions you are required to write should behave
exactly as specified.

Two useful functions are provided for you in this file:

- run_csdp, which runs CSDP from Sage, and

- read_csdp_solution, which reads the solution file generated by CSDP
  and returns the solution matrices.

Take a look at function float_sos below to see how these two functions
are used. If you have any doubts, remarks, suggestions or corrections,
write a post on our ELO forum.

"""

import subprocess
import itertools
import numpy as np
from scipy.misc import imread, imsave
import time
import copy

def run_csdp(filename, solfile):
    """Run CSDP and return True on success, False on failure.

    INPUT:

    - filename -- string with the input file name for csdp.

    - solfile -- string with the name of the file where the solution
      will be stored.

    EXAMPLE:

        if run_csdp('foo.sdpa', 'foo.sol'):
            print 'Success'
        else:
            raise RuntimeError('Failed to solve sdp')

    IMPORTANT:

    For this function to work, the CSDP solver must be callable from
    the command line and its directory must be included in the
    system's path.

    """
    # try:
    out = subprocess.check_output([ 'csdp', filename, solfile ])
    # except:
        # return False

    return True


def read_csdp_solution(filename, block_sizes):
    """Return matrices comprising solution of problem in CSDP format.

    INPUT:

    - filename -- name of solution file.

    - block_sizes -- list with the sizes of the blocks in the correct
      order. As with the SDPA format, a negative number indicates a
      diagonal block.

    RETURN VALUE:

    This function returns a list of the same length as block_sizes
    with the corresponding solution blocks. A nondiagonal block is a
    matrix over RDF. A diagonal block is a vector over RDF.

    EXAMPLE:

    See function float_sos.

    """
    # Make a list of the solution matrices, initialized to zero.
    ret = []
    for s in block_sizes:
        if s < 0:
            ret.append(vector(RDF, -s))
        else:
            ret.append(matrix(RDF, s))

    # Then read the solution.
    with open(filename, 'r') as infile:
        # Discard first line.
        infile.readline()

        # Read the matrices.
        for line in infile:
            if line[0] == '2':
                words = line.split()

                block = int(words[1]) - 1
                i = int(words[2]) - 1
                j = int(words[3]) - 1

                if block < 0 or block >= len(block_sizes):
                    raise RuntimeError('invalid block index')

                if i < 0 or i >= block_sizes[block] \
                   or j < 0 or j >= block_sizes[block]:
                    raise RuntimeError('invalid matrix position')

                ret[block][i, j] = ret[block][j, i] = RDF(words[4])

    return ret


def float_sos(p):
    """Return sos representation of univariate polynomial p.

    If p is not a sum of squares, then this function raises the
    ValueError exception. Otherwise, the function returns a list of
    polynomials giving the sos representation of p. The sos
    representation returned uses floating-point numbers.

    Use this function to see how to run CSDP and read the solution
    using the functions above.

    EXAMPLES:

    Here is an example of a polynomial that is a sum of squares:

        sage: load('hma2.sage')
        sage: x = PolynomialRing(RDF, 'x').gen()
        sage: p = x^4 - 3*x^3 - x^2 + 15
        sage: float_sos(p)
        [-0.6551908751612898*x^2 - 5.636867756363169e-17*x + 3.872983346207417,
         -0.7430582026375091*x^2 + 2.0186843973671262*x,
         0.13634304015422885*x^2]
        sage: sum(q^2 for q in _)
        x^4 - 3.0*x^3 - 0.9999999999999991*x^2 - 4.3662989890336238e-16*x + 15.000000000000002

    And here an example of a polynomial that is not an sos:

        sage: p = x^4 - 1
        sage: float_sos(p)
        [...]
        ValueError: polynomial is not SOS, says CSDP

    """
    if p.degree() % 2 != 0:
        raise ValueError('polynomial has odd degree')
    
    # Generate the SDPA file with the problem.
    out = open('foo.sdpa', 'w')

    out.write('%d\n' % (p.degree() + 1))
    out.write('1\n')
    out.write('%d\n' % (1 + p.degree() // 2))

    # Right-hand side.
    for a in p.list():
        out.write('%f ' % a)

    out.write('\n')

    # Constraints for each degree.
    for deg in xrange(p.degree() + 1):
        for i in xrange(1 + p.degree() // 2):
            j = deg - i

            if j >= 0 and j <= p.degree() // 2 and i <= j:
                out.write('%d 1 %d %d 1.0\n'
                          % (deg + 1, i + 1, j + 1))

    # Run CSDP.
    out.close()

    if not run_csdp('foo.sdpa', 'foo.sol'):
        raise ValueError('polynomial is not SOS, says CSDP')

    # Read the solution.
    sol = read_csdp_solution('foo.sol', [ 1 + p.degree() // 2 ])
    X = sol[0]

    try:
        U = X.cholesky()
    except:
        raise ValueError('solution is not psd, oops!')

    PR = PolynomialRing(RDF, 'x')
    x = PR.gen()
    foo = [ x^k for k in xrange(1 + p.degree() // 2) ]
    vx = vector(PR, foo)

    return list(U.transpose() * vx)


def normalize_matrix(A):
    """Normalize matrix elements to [-1, 1]."""

    l = min(A.list())
    u = max(A.list())

    if l == u:
        if l <= 125:
            return matrix(RDF, A.nrows(), A.ncols(),
                          lambda i, j: -1)
        else:
            return matrix(RDF, A.nrows(), A.ncols(),
                          lambda i, j: 1)
    
    return matrix(RDF, A.nrows(), A.ncols(),
                  lambda i, j: 2 * ((A[i, j] - l) / (u - l)) - 1)


def sdp_filter(in_filename, out_filename, lda, r, block_size = 10,
               border_size = 3, nrounds = 30):
    """Apply deblurring sdp filter to image.

    INPUT:

    - in_filename -- name of input image.

    - out_filename -- name of output image.

    - lda -- lambda parameter.

    - r -- pixels (a, b) and (ap, bp) are considered neighbors if 
      max { |a - ap|, |b - bp| } <= r.

    - block_size -- size of block for image segmentation, in number of
      pixels.

    - border_size -- size of border around a block, in number of
      pixels.

    - nrounds -- how many times the randomized rounding procedure
      should be run.

    """
    # Read the image. The matrix returned has real numbers in the
    # interval [0, 255].
    A = matrix(RDF, imread(in_filename, flatten = True))

    # Matrix with resulting binary image, to be filled by you.
    R = matrix(ZZ, A.nrows(), A.ncols())
    
    ########
    #
    # Here should come your code. It should assemble the final image
    # in the matrix R. Each pixel has a value of either 0 (black) or
    # 255 (white).
    #
    # IMPORTANT:
    #
    # Recall that the matrix A you read has numbers in [0, 255]. Our
    # approach expects numbers in the interval [-1, 1]. To get that,
    # you normalize each block before processing it. If B is the
    # block, use the function normalize matrix:
    #
    # C = normalize_matrix(B)
    # 
    ########

    n_col_segments = int(math.floor(A.ncols() / block_size))
    n_row_segments = int(math.floor(A.nrows() / block_size))

    final_image = np.zeros((A.nrows(), A.ncols()))
    # x, y are 0-indexed
    # returns the segment coordinates and a segment of the full image
    def getSegment((x, y)):
        x_0 = max(0, x*block_size - border_size)
        x_1 = min(A.ncols(), x*block_size + block_size + border_size)
        y_0 = max(0, y*block_size - border_size)
        y_1 = min(A.nrows(), y*block_size + block_size + border_size)
        return x, y, A[x_0:x_1, y_0:y_1]

    segments = list(itertools.product(range(0, n_col_segments), range(0, n_row_segments)))
    segments = map(getSegment, segments)

    x_max = max(map(lambda segment: segment[0], segments))
    y_max = max(map(lambda segment: segment[1], segments))
    def removeBorder(x, y, image):
        if x != 0:
            image = np.delete(image, range(0, border_size), 0)
        if y != 0:
            image = np.delete(image, range(0, border_size), 1)

        if x != x_max:
            image = np.delete(image, range(block_size, block_size + border_size), 0)

        if y != y_max:
            image = np.delete(image, range(block_size, block_size + border_size), 1)                

        return image

    for x, y, segment in segments:
        # normalized segment
        B = normalize_matrix(segment)

        # image size of segment
        I = B.nrows() * B.ncols()


        # contents of sdpa_file
        ## number of constraints
        sdpa_file = str(I + 1) + "\n"
        ## number of blocks
        sdpa_file += "1\n"
        ## block size
        sdpa_file += str(I + 1) + "\n"
        #3 constraint RHS
        sdpa_file += ("1 "* (I + 1)) + "\n"


        # sdpa_file += "0 1 1 1 1.0\n"

        g = vector(B)
        C = np.zeros((I + 1, I + 1))

        def indexToCoords(index):
            y = int(math.floor(index / B.nrows()))
            x = index - y * B.ncols()
            return x, y
        
        def coordsToIndex(x, y):
            return x + y * B.ncols()
        
        def areNeighbors(i, j):
            x_0, y_0 = indexToCoords(i)
            x_1, y_1 = indexToCoords(j)

            return max(abs(x_0 - x_1), abs(y_0 - y_1)) <= r
        
        def validIndex(i):
            return 0 <= i < I

        def getNeighbors(i):
            x, y = indexToCoords(i)
            xs = map(lambda x_rel: x + x_rel, range(-r, r + 1))
            ys = map(lambda y_rel: y + y_rel, range(-r, r + 1))
            xys = itertools.product(xs, ys)
            indices = map(lambda xy: coordsToIndex(xy[0], xy[1]), xys)

            return filter(validIndex, indices)
        
        # add first sum
        for j in range(1, I + 1):
            C[0, j] = 2.0 * g[j-1]
            C[j, 0] = 2.0 * g[j-1]

        # add second sum
        for i in range(1, I + 1):
            for j in range(1, I + 1):
                if i >= j and areNeighbors(i - 1, j - 1):
                    C[i, j] = lda

        # add objective to SDPA file
        for i in range(0, I + 2):
            for j in range(1, I + 2):
                if i >= j and C[i-1, j-1] != 0:
                    # [matrix number] [block number] [i] [j] [c]
                    sdpa_file += "0 1 %(i)s %(j)s %(c)f\n" % {'i': i, 'j': j, 'c': C[i-1, j-1]}

        # Add constraints
        # NB: SDPA is 1-indexed
        for i in range(1, I + 2):
            # [matrix number] [block number] [i] [j] [c]
            sdpa_file += "i 1 i i 1.0\n".replace("i", str(i))
        
        # Solve SDP
        out = open('sdp_filter.sdpa', 'w')
        out.write(sdpa_file)
        out.close()
        run_csdp('sdp_filter.sdpa', 'sdp_filter.sol')

        # Get SDP result
        result = read_csdp_solution('sdp_filter.sol', [ I + 1 ])[0]

        # hyperplane roundings
        V = np.matrix(result.cholesky())
        f = np.zeros(I)
        f_max = np.zeros(I)

        def f_obj(g, x):
            result = np.sum(map(lambda i: 2 * x[i] * g[i], range(0, I)))

            if (lda > 0):
                neighbors = [(i, neighbor) for i in range(0, I) for neighbor in getNeighbors(i)]
                result += lda * np.sum(map(lambda ij: x[ij[0]] * x[ij[1]], neighbors))

            return result
        
        current_max = -10e9
        start = time.time()
        for n_round in range(0, nrounds):
            z = np.random.normal(0, 1, I + 1)

            # V[0] = e
            if (np.inner(z, V[0]) < 0):
                z *= -1

            for i in range(1, I + 1):
                # note that the first element of f corresponds with the first pixel, so f[0] <=> V[1]
                f[i-1] = np.sign(np.inner(z, V[i]))
           
            # Keep f with max objective value
            f_val = f_obj(g, f)
            if (current_max < f_val):
                f_max = copy.copy(f)
                current_max = f_val

        m = block_size + 2*border_size
        n = block_size + 2*border_size
        if x*block_size < border_size:
            m -= border_size - x*block_size
        
        if y*block_size < border_size:
            n -= border_size - y*block_size

        if x == x_max:
            m -= border_size
        
        if y == y_max:
            n -= border_size

        f_matrix = f_max.reshape(m,n)
        f_resized = (1+f_matrix)/2 * 255
        image_block = removeBorder(x, y, f_resized)
        final_image[x*block_size:(x+1)*block_size,y*block_size:(y+1)*block_size] = image_block
        imsave(out_filename, final_image)

def interval_minimum(p, a, b, filename):
    """Write SDP whose optimal is minimum of p on [a, b].

    This function writes to a file called filename a semidefinite
    program in SDPA format whose optimal value is the minimum of the
    polynomial p on the interval [a, b]. Notice p can have even or odd
    degree.

    INPUT:

    - p -- a polynomial over RDF.

    - a, b -- endpoints of interval, a < b.

    - filename -- name of file for SDPA output.

    """
    pass


# Local variables:
# mode: python
# End:
