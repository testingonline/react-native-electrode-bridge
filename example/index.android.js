/**
 * Sample React Native App
 * https://github.com/facebook/react-native
 * @flow
 */

 //@flow

import React, { Component } from 'react';
import {
  AppRegistry,
  StyleSheet,
  Text,
  View,
  TouchableOpacity,
  Slider
} from 'react-native';
import { electrodeBridge } from 'react-native-electrode-bridge';

// Inbound event/request types
const NATIVE_REQUEST_EXAMPLE_TYPE = "native.request.example";
const NATIVE_EVENT_EXAMPLE_TYPE = "native.event.example";

// Outbound event/request types
const REACTNATIVE_REQUEST_EXAMPLE_TYPE = "reactnative.request.example";
const REACTNATIVE_EVENT_EXAMPLE_TYPE = "reactnative.event.example";


class ElectrodeBridgeExample extends Component {

  constructor(props) {
    super(props);

    this.state = {
      bgColor: 'rgb(0,0,0)',
      pendingInboundRequest: false,
      pendingInboundRequestPromiseResolve: null,
      pendingInboundRequestPromiseReject: null,
      logText: ">>>"
    };
  }

  componentDidMount() {
    electrodeBridge.addListener(NATIVE_EVENT_EXAMPLE_TYPE,
    this._logIncomingEvent.bind(this));

    electrodeBridge.registerRequestHandler(NATIVE_REQUEST_EXAMPLE_TYPE,
      this._receivedRequest.bind(this));
  }

  _receivedRequest(data) {
    this._setLoggerText(`Request received. Payload : ${JSON.stringify(data)}`);
    return new Promise((resolve,reject) => {
        this.setState({
          pendingInboundRequest: true,
          pendingInboundRequestPromiseReject: reject,
          pendingInboundRequestPromiseResolve: resolve
        });
    });
  }

  render() {
    return (
      <View style={styles.container} backgroundColor={this.state.bgColor}>
        <View style={{flexDirection:'column', justifyContent: 'space-between'}}>
        <Text style={styles.logger}>
          {this.state.logText}
        </Text>
        <View style={styles.buttonGroup}>
          <View style={{flexDirection:'row'}}>
            {this._renderButtonGroupTitle('Send request', 'gold')}
            {this._renderButton('with payload', 'royalblue',
              this._sendRequestWithPayload.bind(this))}
            {this._renderButton('w/o payload', 'royalblue',
              this._sendRequestWithoutPayload.bind(this))}
          </View>
        </View>
        <View style={styles.buttonGroup}>
          <View style={{flexDirection:'row'}}>
            {this._renderButtonGroupTitle('Emit event', 'gold')}
            {this._renderButton('with payload', 'royalblue',
              this._emitEventWithPayload.bind(this))}
            {this._renderButton('w/o payload', 'royalblue',
              this._emitEventWithoutPayload.bind(this))}
          </View>
        </View>
        {this._renderIncomingRequestButtonGroup()}
        </View>
      </View>
    );
  }

  _sendRequestWithPayload() {
    electrodeBridge
      .sendRequestToNative(REACTNATIVE_REQUEST_EXAMPLE_TYPE, { hello: "world" })
      .then(resp => { this._logIncomingSuccessResponse(resp); })
      .catch(err => { this._logIncomingFailureResponse(err); });
  }

  _sendRequestWithoutPayload() {
    electrodeBridge
      .sendRequestToNative(REACTNATIVE_REQUEST_EXAMPLE_TYPE)
      .then(resp => { this._logIncomingSuccessResponse(resp); })
      .catch(err => { this._logIncomingFailureResponse(err); });
  }

  _emitEventWithPayload() {
    electrodeBridge
      .emitEventToNative(REACTNATIVE_EVENT_EXAMPLE_TYPE, { randFloat: Math.random()});
  }

  _emitEventWithoutPayload() {
    electrodeBridge
      .emitEventToNative(REACTNATIVE_EVENT_EXAMPLE_TYPE);
  }

  _logIncomingEvent(evt) {
    this._setLoggerText(`Event Received. Payload : ${JSON.stringify(evt)}`);
  }

  _logIncomingSuccessResponse(resp) {
    this._setLoggerText(`Response success. Payload : ${JSON.stringify(resp)}`)
  }

  _logIncomingFailureResponse(resp) {
    this._setLoggerText(`Response failure. Payload : ${JSON.stringify(resp)}`)
  }

  _setLoggerText(text) {
    this.setState({logText: `>>> ${text}`});
  }

  _renderIncomingRequestButtonGroup() {
    let component;
    if (this.state.pendingInboundRequest === true) {
      component =
      <View style={styles.buttonGroupIncomingRequest}>
        <View style={{flexDirection:'row'}}>
          {this._renderButtonGroupTitle('Resolve request', 'cornsilk')}
          {this._renderButton('with payload', 'green',
            this._resolveInboundRequestWithPayload.bind(this))}
          {this._renderButton('w/o payload', 'green',
            this._resolveInboundRequestWithoutPayload.bind(this))}
        </View>
        <View style={{flexDirection:'row'}}>
          {this._renderButtonGroupTitle('Reject request', 'cornsilk')}
          {this._renderButton('w/o payload', 'red',
            this._rejectInboundRequest.bind(this))}
        </View>
      </View>
    } else {
      component = <View/>
    }
    return component;
  }

  _resolveInboundRequestWithPayload() {
    this.state.pendingInboundRequestPromiseResolve({ hello: "world" });
    this._cleanpendingInboundRequestState();
  }

  _resolveInboundRequestWithoutPayload() {
    this.state.pendingInboundRequestPromiseResolve({});
    this._cleanpendingInboundRequestState();
  }

  _rejectInboundRequest() {
    this.state.pendingInboundRequestPromiseReject(new Error("boum"));
    this._cleanpendingInboundRequestState();
  }

  _renderButtonGroupTitle(title, color) {
    return (
      <Text style={[styles.buttonGroupTitle, { color: color }]}>{title}</Text>
    )
  }

  _renderButton(name, color, onClickCallback) {
    return (
      <TouchableOpacity style={styles.button} onPress={onClickCallback}>
        <Text style={[styles.buttonText, { backgroundColor: color }]} onPress={onClickCallback}>
          {name}
        </Text>
      </TouchableOpacity>
    );
  }

  _cleanpendingInboundRequestState() {
    this.setState({
      pendingInboundRequest: false,
      pendingInboundRequestPromiseReject: null,
      pendingInboundRequestPromiseResolve: null
    });
  }
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    flexDirection: 'column',
    justifyContent: 'space-between',
  },
  buttonGroup: {
    backgroundColor: 'dimgrey',
    marginTop: 10,
    borderColor: 'cadetblue',
    borderBottomWidth: 1,
    borderTopWidth: 1
  },
  buttonGroupIncomingRequest: {
    backgroundColor: 'slategrey',
    marginTop: 10,
    borderColor: 'gold',
    borderBottomWidth: 1,
    borderTopWidth: 1
  },
  buttonGroupTitle: {
    flex:1,
    fontSize: 15,
    padding: 1,
    margin:10,
    textAlign: 'left'
  },
  button: {
    flex:1,
    margin: 10,
    borderWidth: 1,
    borderRadius: 2,
    borderColor: 'black'
  },
  buttonText: {
    textAlign: 'center',
    fontSize: 15,
    color: 'seashell'
  },
  logger: {
    margin: 10,
    fontSize: 12
  }
});

AppRegistry.registerComponent('ElectrodeBridgeExample', () => ElectrodeBridgeExample);