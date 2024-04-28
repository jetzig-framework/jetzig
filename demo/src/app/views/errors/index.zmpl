<style>
div {
  padding: 15px;
  position: absolute;
  top: 50%;
  left: 50%;
  -ms-transform: translateX(-50%) translateY(-50%);
  -webkit-transform: translate(-50%,-50%);
  transform: translate(-50%,-50%);
  text-align: center;
}
</style>
<div>
  <img src="/jetzig.png" />
  <h1 style="font-size: 6rem; font-family: sans-serif; color: #f7931e">{{.error.code}}</h1>
  <h1 style="font-size: 4rem; font-family: sans-serif; color: #39b54a">{{.error.message}}</h1>
</div>
