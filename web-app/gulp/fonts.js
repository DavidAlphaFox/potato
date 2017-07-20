/* Fonts related tasks */
var gulp       = require('gulp');
var flatten    = require('gulp-flatten');
var plumber    = require("gulp-plumber");

var basePath   = global.basePath;

gulp.task('fonts:symb', function() {
    var source = basePath.src + 'fonts/symb/';
    gulp.
        src([ source + '**/*.{ttf,woff,eot}' ]).
        pipe(plumber()).
        pipe(flatten()).
        pipe(gulp.dest(basePath.dest+'fonts/symb'));
});

gulp.task('fonts:noto', function() {
    var source = basePath.src + 'fonts/Noto/';
    gulp.
        src([ source + '**/*.{ttf,woff,eot}' ]).
        pipe(plumber()).
        pipe(flatten()).
        pipe(gulp.dest(basePath.dest+'fonts/Noto'));
});

gulp.task('fonts:package', [ 'fonts:symb', 'fonts:noto' ]);
